% roi_activity - call roi_connectivity_process to compute
%                                connectivity between ROIs
% Usage:
%  EEG = roi_activity(EEG, 'key', 'val', ...);
%
% Inputs:
%  EEG - EEGLAB dataset
%
% Required inputs:
%  'leadfield'   - [string or struct] leadfield structure (Fieldtrip)
%                  or file containing Fieldtrip or Brainstrom leadfield
%                  matrix.
%  'sourcemodel' - [string] source model file also containing Atlas info.
% 
% Optional inputs:
%  'sourcemodel2mni' - [9x float] homogeneous transformation matrix to convert
%                  sourcemodel to MNI space.
%  'sourcemodelatlas' - [string] name of Atlas to use (must be contained
%                       in Atlas field of the sourcemodel file.
%  'morder'    - [interger] Autoregressive model order (default is 20)
%  'nPCA'      - [interger] Number of PCA component for each ROI. Each ROI
%                is made of many voxel. Instead of averaging their activity,
%                this function takes the x first PCA components, then use
%                these to compute connectivity (default is 3)
%  'naccu'     - [interger] For bootstrap, number of accumulation. Default is 
%                none.
%  'eloretareg' - [float] regularization term for eLoreta. Default is 0.05.
%  'trgc'      - ['on'|'off'] compute time-reverse Granger Causality. Default
%                is 'on'.
%  'crossspec' - ['on'|'off'] compute cross-spectrum from which coherence can
%                be derived. Default is 'on'.
%  'roiactivity'  - ['on'|'off'] compute ROI activity. Default is on. If
%                you just need voxel activity, you can set this option to
%                'off'.
%  'exportvoxact' - ['on'|'off'] export voxel activity in EEG.roi.source_voxel_data
%                These array are huge, so the default is 'off'.
%
% Output:
%  EEG - EEGLAB dataset with field 'roi' containing connectivity info.
%  source_voxel_data - voxel data activity (voxels x times x trials).
%                      Usually several Gb in size.
%
% Author: Stefan Haufe and Arnaud Delorme
%
% Example: call pop_roi_activity instead because it will
% compute the leadfield matrix automatically using Dipfit information.

% Copyright (C) Arnaud Delorme, arnodelorme@gmail.com
%
% Redistribution and use in source and binary forms, with or without
% modification, are permitted provided that the following conditions are met:
%
% 1. Redistributions of source code must retain the above copyright notice,
% this list of conditions and the following disclaimer.
%
% 2. Redistributions in binary form must reproduce the above copyright notice,
% this list of conditions and the following disclaimer in the documentation
% and/or other materials provided with the distribution.
%
% THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
% AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
% IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
% ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
% LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
% CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
% SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
% INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
% CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
% ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF
% THE POSSIBILITY OF SUCH DAMAGE.

function [EEG, source_voxel_data] = roi_activity(EEG, varargin)

if nargin < 2
    help roi_activity;
    return
end

% decode input parameters
% -----------------------
g = finputcheck(varargin, { ...
    'leadfield'  {'struct' 'string'}  {{} {}}             '';
    'headmodel'   'string'  { }             ''; % sometimes useful when loading volume to see which voxels are inside/outside
    'sourcemodel' 'string'  { }             '';
    'sourcemodel2mni' 'real'    { }         [];
    'sourcemodelatlas' 'string'    { }      '';
    'sourceparams'   'cell'    { }          { 0.05 };
    'sourceanalysis' 'string'    { 'fieldtrip' 'roiconnect' } 'fieldtrip';
    'sourcemethod'   'string'    { }        'eloreta';
    'nPCA'        'integer' { }              3;
    'downsample'  'integer' { }              1;
    'roiactivity' 'string' { 'on' 'off' }    'on';
    'exportvoxact' 'string' { 'on' 'off' }    'on';
    'outputdir'   'string'  { }              '' }, 'roi_activity');
if ischar(g), error(g); end
if isempty(g.leadfield), error('Leadfield is mandatory parameter'); end
     
% GO TO BRAINSTORM-MASTER3 folder AND START BRAINSTORM
p = fileparts(which('roi_activity'));
addpath(fullfile(p, 'libs/Daniele_ARMA'));
addpath(fullfile(p, 'libs/export_fig'));
addpath(fullfile(p, 'libs/haufe'));
addpath(fullfile(p, 'libs/mvgc_v1.0'));
addpath(fullfile(p, 'libs/mvgc_v1.0/core'));
addpath(fullfile(p, 'libs/mvgc_v1.0/stats'));
addpath(fullfile(p, 'libs/mvgc_v1.0/utils'));
addpath(fullfile(p, 'libs/nolte'));
addpath(fullfile(p, 'libs/ssgc_v1.0'));
addpath(fullfile(p, 'libs/brainstorm'));

%%% Creating result folder
if ~isempty(g.outputdir)
    mkdir(fullfile( g.outputdir, 'data'));
end

% Cortex mesh or volume
% ---------------------
[~,~,ext] = fileparts(g.sourcemodel);

if strcmpi(ext, '.head')
    [~, grid, labels, strlabels ] = load_afni_atlas(g.sourcemodel, g.headmodel, g.sourcemodel2mni, g.downsample);
    uniqueROIs = unique(labels);
    nROI = length(uniqueROIs);
    cortex.Atlas(1).Name = g.sourcemodelatlas;
    for iROI = 1:nROI
        indVertices = find(labels == uniqueROIs(iROI));
        cortex.Atlas(1).Scouts(iROI).Label    = strlabels{iROI};
        cortex.Atlas(1).Scouts(iROI).Vertices = indVertices;
    end
    cortex.Vertices = grid;
else
    cortex = load(g.sourcemodel);
    if isfield(cortex, 'Faces')
        % make brainstorm coordinate system consistent with MNI coordinates for
        % plotting (in terms of axis directions)
        disp('Brainstorm cortex mesh detected - transforming to MNI coordinates');
        tf = traditionaldipfit(g.sourcemodel2mni);
        pos      = tf*[cortex.Vertices ones(size(cortex.Vertices,1),1)]';
        pos      = pos';
        cortex.Vertices = pos(:,1:3);
    elseif isfield(cortex, 'cortex') && isfield(cortex, 'atlas')
        hm = cortex;
        clear cortex;
        % align with MNI coordinates
        tf = traditionaldipfit(g.sourcemodel2mni);
        pos      = tf*[hm.cortex.vertices ones(size(hm.cortex.vertices,1),1)]';
        pos      = pos';
        cortex.Vertices = pos(:,1:3);
        cortex.Faces = hm.cortex.faces;

        % make Alejandro Atlas definition compatible with Brainstrom one
        nROI = length(hm.atlas.label);
        cortex.Atlas(1).Name = g.sourcemodelatlas;
        for iROI = 1:nROI
            indVertices = find(hm.atlas.colorTable == iROI);
            cortex.Atlas(1).Scouts(iROI).Label    = hm.atlas.label{iROI};
            cortex.Atlas(1).Scouts(iROI).Vertices = indVertices;
        end
    elseif isnumeric(cortex) && mod(size(cortex,1),3) == 0 && size(cortex,2) == 6
        % NFT matrix
        cortextmp = cortex;
        clear cortex;
        cortex.Vertices = cortextmp(:,1:3);
        cortex.Atlas(1).Name = g.sourcemodelatlas;
    elseif ~isfield(cortex, 'Vertices')
        % code below is functional to load a mesh
        % However, need to align with an Atlas
        % This can be achieve with Fieldtrip functions
        sourcemodelOriOld = ft_read_headshape(fullfile(ftPath, 'template', 'sourcemodel', 'cortex_20484.surf.gii'));

        error('Unknown mesh format')
    end
end

% Select Atlas
% ------------
found = false;
for iAtlas = 1:length(cortex.Atlas)
    if strcmpi(cortex.Atlas(iAtlas).Name, g.sourcemodelatlas)
        cortex.Atlas = cortex.Atlas(iAtlas);
        found = true;
        break
    end
end
if ~found
    error('Atlas not found');
end

% leadfield matrix (Brainstorm or Fieldtrip)
% ------------------------------------------
if ~isstruct(g.leadfield)
    leadfield = load(g.leadfield, '-mat');
else
    leadfield = g.leadfield;
end
if isstruct(leadfield) && isfield(leadfield, 'roiconnectleadfield') 
    leadfield = leadfield.roiconnectleadfield;
elseif isstruct(leadfield) && isfield(leadfield, 'Gain') 
    % brainstorm
    % make format compatible with Stefan's routines
    leadfield = permute(reshape(leadfield.Gain, [], 3, nvox), [1 3 2]);
elseif isstruct(leadfield) && isfield(leadfield, 'leadfield') 
    % fieldtrip
    oldLeadfield = leadfield;
    leadfield.gain = reshape( [ leadfield.leadfield{:} ], [length(leadfield.label) 3 length(leadfield.leadfield)]);
    leadfield.gain = permute(leadfield.gain, [1 3 2]);
    leadfield = leadfield.gain;
elseif isfield(leadfield, 'LFM')
    % NFT
    leadfield = leadfield.LFM;
else
    disp('Warning: unknown leadfield matrix format, assuming array of gain values');
end

nvox = size(cortex.Vertices, 1);
nvox2 = size(leadfield,2);
if ~isequal(nvox, nvox2)
    error('There must be the same number of vertices/voxels in the leadfield and source model');
end
if ~isequal(size(leadfield,1), EEG.nbchan)
    error('There must be the same number of channels in the leadfield and in the dataset');
end

% use frequency resolution of 0.5 Hz
fres = EEG.srate;

% from the MVGC toolbox, compute frequencies in Hz for a
frqs = sfreqs(fres, EEG.srate);

%% source reconstruction
if strcmpi(g.sourceanalysis, 'roiconnect')
    % common average reference transform
    H = eye(EEG.nbchan) - ones(EEG.nbchan) ./ EEG.nbchan;

    % apply to data and leadfield
    EEG.data = reshape(H*EEG.data(:, :), EEG.nbchan, EEG.pnts, EEG.trials);
    leadfield = reshape(H*leadfield(:, :), EEG.nbchan, nvox, 3);

    % eLORETA inverse projection kernel
    disp('Computing eLoreta...');
    P_eloreta = mkfilt_eloreta_v2(leadfield, g.sourceparams{:});
    
    % project to source space
    source_voxel_data = reshape(EEG.data(:, :)'*P_eloreta(:, :), EEG.pnts*EEG.trials, nvox, 3);

else
    % transform the data to continuous so we can get an estimate for each sample
    EEG2 = EEG;
    EEG2.data = EEG2.data(:,:);
    EEG2.pnts = size(EEG2.data,2);
    EEG2.trials = 1;
    EEG2 = eeg_checkset(EEG2);
    dataPre = eeglab2fieldtrip(EEG2, 'preprocessing', 'dipfit');  
    
    % prepare data
    cfg = [];
    cfg.channel = {'all', '-EOG1'};
    cfg.reref = 'yes';
    cfg.refchannel = {'all', '-EOG1'};
    dataPre = ft_preprocessing(cfg, dataPre);

    % load head model and prepare leadfield matrix
    vol = load('-mat', g.headmodel);

    % source reconstruction
    cfg             = [];
    cfg.method      = g.sourcemethod;
    try
        cfg.(g.sourcemethod) = struct(g.sourceparams{:});
    catch, end
    cfg.sourcemodel = oldLeadfield;
    cfg.headmodel   = vol.vol;
    cfg.keeptrials  = 'yes';
    source          = ft_sourceanalysis(cfg, dataPre);  % compute the source
    
    % reformat for ROI analysis below
    source_voxel_data = reshape([ source.avg.mom{:} ], 3, size(source.avg.mom{1},2), length(source.avg.mom));
    source_voxel_data = permute(source_voxel_data, [2 3 1]);
end
    
% number of ROIs in the Desikan-Killiany Atlas
nROI = length(cortex.Atlas.Scouts);

% ROI labels
labels = {cortex.Atlas.Scouts.Label};

% keep only the first nPCA strongest components for each ROI
if strcmpi(g.roiactivity, 'on')
    disp('Computing ROI activity...');
    source_roi_data = [];
    
    for iROI = 1:nROI
        ind_roi = cortex.Atlas.Scouts(iROI).Vertices;
        [source_roi_power(iROI), source_roi_power_norm(iROI)] = roi_getpower(source_voxel_data, ind_roi);
        source_roi_data(:, :, iROI) = roi_getact(source_voxel_data, ind_roi, g.nPCA);
    end

    % version with nPCA components
    source_roi_data = permute(reshape(source_roi_data, EEG.pnts, EEG.trials, []), [3 1 2]);
else
    source_roi_data = [];
    source_roi_power_norm = [];
end
disp('Done');

% Output paramters
EEG.roi.cortex    = cortex;
EEG.roi.atlas     = cortex.Atlas.Scouts;
if strcmpi(g.exportvoxact, 'on')
    EEG.roi.source_voxel_data     = source_voxel_data; % large
end
EEG.roi.source_roi_data       = single(source_roi_data);
EEG.roi.source_roi_power_norm = source_roi_power_norm; % used for cross-sprectum
EEG.roi.freqs     = frqs;
EEG.roi.nPCA      = g.nPCA;
EEG.roi.nROI      = nROI;
EEG.roi.atlas     = cortex.Atlas;
EEG.roi.srate     = EEG.srate;
EEG.roi.leadfield = g.leadfield;
EEG.roi.headmodel = g.headmodel;
EEG.roi.parameters = varargin;
if exist('P_eloreta', 'var')
    EEG.roi.P_eloreta = single(P_eloreta);
end

