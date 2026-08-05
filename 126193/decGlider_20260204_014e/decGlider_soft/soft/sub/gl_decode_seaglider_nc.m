% ------------------------------------------------------------------------------
% This decodes seaglider data from a single yo NetCDF text format and places
% it in a matlab structure for subsequent conversion to EGO netcdf format
% by EGO routines.
%
% SYNTAX :
% [o_rawDataStruct] = gl_decode_seaglider_nc(a_ncFileNameIn)
%
% INPUT PARAMETERS :
%   a_ncFileNameIn : name of the input NetCDF file from a yo
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
%   01/27/2020 - RNU - creation
% ------------------------------------------------------------------------------
function [o_rawDataStruct] = gl_decode_seaglider_nc(a_ncFileNameIn)

% output parameter initialization
o_rawDataStruct = [];

% QC flag values (numerical)
global g_decGl_qcDef;


% read data from the .nc file
rawDataFull = gl_seaglider_netcdf_nc2matlab(a_ncFileNameIn);

% merge parameter measurements on the same time axis
rawDataFull = gl_seaglider_merge_nc_data(rawDataFull);

% output structure
rawData = [];
rawData.source = rawDataFull.source;
rawData.vars_time = rawDataFull.nc;
rawData.vars_time_gps = get_gps_data(rawDataFull);

% add current estimates
rawData.current = [];
fieldNames = fields(rawDataFull.VAR);
idF = find(contains(fieldNames, 'surface_curr_') | contains(fieldNames, 'depth_avg_curr_'));
for id = idF'
   fieldName = fieldNames{id};
   rawData.current.(fieldName) = rawDataFull.VAR.(fieldName).DATA;
   if (strcmp(fieldName(end-2:end), '_qc'))
      % QC is provided as 1 char
      rawData.current.(fieldName) = int8(str2double(rawData.current.(fieldName)));
      if (any(rawData.current.(fieldName) == 6))
         rawData.current.(fieldName)(rawData.current.(fieldName) == 6) = g_decGl_qcDef;
         fprintf('WARNING: Imported netCDF var ''%s'' contains ''6'' values not managed by EGO format => replaced by ''%d''\n', fieldName, g_decGl_qcDef);
      end
   end
   if (isfield(rawDataFull.VAR.(fieldName).ATT, 'units') && ...
         strcmp(rawDataFull.VAR.(fieldName).ATT.units, 'm/s'))
      % convert m/s to cm/s
      rawData.current.(fieldName) = rawData.current.(fieldName)*100;
   end
end

% compute and add derived parameters
rawData = gl_add_derived_parameters(rawData);

o_rawDataStruct = rawData;

return

% ------------------------------------------------------------------------------
% Parse GPS data collected in a NetCDF file.
%
% SYNTAX :
%  [o_structure] = gl_parse_gps_data(a_structure)
%
% INPUT PARAMETERS :
%   a_structure : input GPS data structure (from NetCDF file)
%
% OUTPUT PARAMETERS :
%   a_structure : output parsed GPS data
%
% EXAMPLES :
%
% SEE ALSO :
% AUTHOR : Jean-Philippe Rannou (Capgemini) (jean.philippe.rannou@partenaire-exterieur.ifremer.fr)
% ------------------------------------------------------------------------------
% RELEASES :
%   01/27/2020 - RNU - creation
% ------------------------------------------------------------------------------
function [o_structure] = get_gps_data(a_structure)

% output data initialization
o_structure = [];

if (isfield(a_structure.VAR, 'log_gps_time') && ...
      isfield(a_structure.VAR, 'log_gps_lon') && ...
      isfield(a_structure.VAR, 'log_gps_lat'))
   o_structure.time = (a_structure.VAR.log_gps_time.DATA)';
   o_structure.longitude = (a_structure.VAR.log_gps_lon.DATA)';
   o_structure.latitude = (a_structure.VAR.log_gps_lat.DATA)';
end

return
