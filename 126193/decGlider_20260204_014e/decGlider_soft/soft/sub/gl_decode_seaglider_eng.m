% ------------------------------------------------------------------------------
% This decodes seaglider data from a single yo eng text format and places
% it in a matlab structure for subsequent conversion to EGO netcdf format
% by EGO routines.
%
% SYNTAX :
% [o_rawDataStruct] = gl_decode_seaglider_eng(a_engFileNameIn)
%
% INPUT PARAMETERS :
%   a_engFileNameIn : name of the input .eng file from a yo
%
% OUTPUT PARAMETERS :
%   o_rawDataStruct : processed data structure
%
% EXAMPLES :
%
% SEE ALSO :
% AUTHOR : Jean-Philippe Rannou (Capgemini) (jean.philippe.rannou@partenaire-exterieur.ifremer.fr)
% ------------------------------------------------------------------------------
% RELEASES :
%   06/09/2015 - RNU - creation
% ------------------------------------------------------------------------------
function [o_rawDataStruct] = gl_decode_seaglider_eng(a_engFileNameIn)

% output parameter initialization
o_rawDataStruct = [];


% read data from the different input files

% read data from the main p*.eng file
rawDataFull = gl_seaglider_eng_ascii2matlab(a_engFileNameIn);

% read data from the ppc*a.eng file (downcast CTD), if any
[engFilePathName, engFileName, ext] = fileparts(a_engFileNameIn);
engCtdDownFileName = ['ppc' engFileName(2:end) 'a.eng'];
engCtdDownFilePathName = [engFilePathName filesep engCtdDownFileName];
bOnly = 0;
if (exist(engCtdDownFilePathName, 'file') == 2)
   rawDataFull = gl_seaglider_ctd_eng_ascii2matlab( ...
      rawDataFull, engCtdDownFilePathName, 'a', bOnly);
else
   bOnly = 1;
end

% read data from the ppc*b.eng file (upcast CTD)
engCtdUpFileName = ['ppc' engFileName(2:end) 'b.eng'];
engCtdUpFilePathName = [engFilePathName filesep engCtdUpFileName];
rawDataFull = gl_seaglider_ctd_eng_ascii2matlab( ...
   rawDataFull, engCtdUpFilePathName, 'b', bOnly);

% merge p*.eng and ppc*a/b.eng data
rawDataFull = gl_seaglider_merge_eng_data(rawDataFull);

% master list of all fields, initialize it with the first dive
allEngFields = fieldnames(rawDataFull.eng);

% create master time channels
rawDataFull.vars_dives.time = rawDataFull.eng.start;
rawDataFull.vars_time.juld = rawDataFull.eng.time_eng_juld;

% copy data from eng structure to vars structures
for idF = 1:length(allEngFields)
   if (strcmp(allEngFields{idF}, 'data') || ...
         strcmp(allEngFields{idF}, 'time_eng_juld'))
      continue
   elseif (strncmp(allEngFields{idF}, 'comment', length('comment')) || ...
         strncmp(allEngFields{idF}, 'basestation_version', length('basestation_version')))
      rawDataFull.vars_dives.(allEngFields{idF}) = rawDataFull.eng.(allEngFields{idF});
   elseif length(rawDataFull.eng.(allEngFields{idF})) == ...
         length(rawDataFull.vars_dives.time)
      % length of data is one, i.e. a single entry per dive
      rawDataFull.vars_dives.(allEngFields{idF}) = rawDataFull.eng.(allEngFields{idF});
   else
      rawDataFull.vars_time.(allEngFields{idF}) = rawDataFull.eng.(allEngFields{idF});
   end
end

% save the data as a .mat file so it can be passed to the netcdf file generator
rawData = [];
rawData.source = rawDataFull.source;
rawData.vars_time = rawDataFull.vars_time;

% add GPS data from p*.log file
logFilePathname = [a_engFileNameIn(1:end-4) '.log'];
rawData.vars_time_gps = gl_seaglider_get_gps_in_log(logFilePathname);

% compute and add derived parameters
rawData = gl_add_derived_parameters(rawData);

o_rawDataStruct = rawData;

return
