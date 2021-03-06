% roi_getact() - compute activity of a given ROI (region of interest)
%
% Usage:
%    [power, powernorm] = roi_getact(roi_data, ind_roi);
%    [power, powernorm] = roi_getact(roi_data, ind_roi, nPCA);
%
% Inputs:
%    roi_data - [times x voxels x trials] source activity data
%    ind_roi  - indices of voxels for the ROI
%    nPCA     - number of PCA components (default is 1).

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

function source_roi_data = roi_getact(source_voxel_data, ind_roi, nPCA)

if nargin < 2
    help roi_getact;
    return;
end

if nargin < 3
    nPCA = 1;
end

% optional z-scoring, this makes the PCA independent of the power in each
% voxel, and favors to find components that are consistently expressed in
% many voxels rather than only in a few voxels with strong power (which
% may leak from a neighboring region)
data_  = source_voxel_data(:, ind_roi, :);
data_(:, :) = zscore(data_(:, :));
if nPCA == 1
    [source_roi_data, ~, ~] = svds(double(data_(:, :)), nPCA); 
else
    % old code
    [data_, ~, ~] = svd(data_(:, :), 'econ'); % WARNING SHOULD USE SVDS for SPEED
                                               % however, sometime polarity
                                               % inverted compared to svds
                                               % Should not have an
                                               % incidence but keeping the
                                               % code for now
    source_roi_data = data_(:, 1:nPCA);
end
