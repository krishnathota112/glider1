% ------------------------------------------------------------------------------
% Create EGO netCDF file from json file (variable definition + meta-data
% information) and matlab structure (data measurements from the glider).
%
% SYNTAX :
% [o_ok] = gl_generate_ego_file(a_jsonDeployData, a_rawDataStruct, ...
%   a_slocumCurrent, a_ncFileName, a_applyRtqc)
%
% INPUT PARAMETERS :
%   a_jsonDeployData  : data of the json deployment file
%   a_rawDataStruct   : data structure
%   a_slocumCurrent   : slocum current estimates
%   a_ncFileName      : output netCDF file path name
%   a_applyRtqc       : apply RTQC tests on output EGO file data
%
% OUTPUT PARAMETERS :
%   o_ok : ok flag (1 if creation process succeeded, 0 otherwise)
%
% EXAMPLES :
%
% SEE ALSO :
% AUTHOR : Jean-Philippe Rannou (Capgemini) (jean.philippe.rannou@partenaire-exterieur.ifremer.fr)
% ------------------------------------------------------------------------------
% RELEASES :
%   06/04/2013 - RNU - creation
% ------------------------------------------------------------------------------
function [o_ok] = gl_generate_ego_file(a_jsonDeployData, a_rawDataStruct, ...
   a_slocumCurrent, a_ncFileName, a_applyRtqc)

% output parameters initialization
o_ok = 0;

% decoder version
global g_decGl_decoderVersion;

% real time processing
global g_decGl_realtimeFlag;

% report information structure
global g_decGl_reportStruct;

% variable names added to the .mat structure
global g_decGl_directEgoVarPathName;
g_decGl_directEgoVarPathName = unique(g_decGl_directEgoVarPathName);

% QC flag values
global g_decGl_qcNoQc;

% meta-data for derived parameters
global g_decGl_derivedParamMetaData;

% type of the glider to process
global g_decGl_gliderType;

% variable names defined in the json deployment file
global g_decGl_egoVarName;
global g_decGl_gliderVarName;

% flag for HR data
global g_decGl_hrDataFlag;

% NetCDF file compression information
global g_decGl_netCDFCompressionFlag;
global g_decGl_netCDFDeflateLevel;
global g_decGl_netCDFCompressAll;

% add PHASE2 computed from technical data
global g_decGl_addPhase2;

% verbose mode flag
VERBOSE_MODE = 0;


% date of all current date information store in the file
currentDate = gl_now_utc;
fileDate = datestr(currentDate, 'yyyymmddHHMMSS');

% variable definition + meta-data information from json file
metaData = a_jsonDeployData;

% create entries for <PARAM>_ADJUSTED
if (isfield(metaData, 'parametersList'))
   newParamAdj = [];
   for idP = 1:length(metaData.parametersList)
      if (iscell(metaData.parametersList))
         paramStruct = metaData.parametersList{idP};
      else
         paramStruct = metaData.parametersList(idP);
      end
      if (isfield(paramStruct, 'adjusted_variable_name'))
         if (~isempty(paramStruct.adjusted_variable_name))
            paramAdj = paramStruct;
            paramAdj.variable_name = paramAdj.adjusted_variable_name;
            paramAdj.ego_variable_name = [paramAdj.ego_variable_name '_ADJUSTED'];
            paramAdj.ancillary_variable = [paramAdj.ego_variable_name '_QC'];
            glVarName = paramAdj.variable_name;
            sep = strfind(glVarName, '.');
            if (~isempty(sep))
               glVarName = glVarName(sep(end)+1:end);
            end
            paramAdj.glider_original_parameter_name = glVarName;
            newParamAdj{end+1} = paramAdj;
         end
      end
   end
   if (~isempty(newParamAdj))
      metaData.parametersList = [metaData.parametersList newParamAdj];
   end
end

% update json deployment information
% clean the DOXY (or DOXY2) to MOLAR_DOXY link
if (isfield(metaData, 'parametersList'))
   for idP = 1:length(metaData.parametersList)
      if (iscell(metaData.parametersList))
         paramStruct = metaData.parametersList{idP};
      else
         paramStruct = metaData.parametersList(idP);
      end
      if (isfield(paramStruct, 'ego_variable_name') && ...
            isfield(paramStruct, 'variable_name') && ...
            isfield(paramStruct, 'glider_original_parameter_name'))
         if ((strcmp(paramStruct.ego_variable_name, 'DOXY') || ...
               strcmp(paramStruct.ego_variable_name, 'DOXY2')) && ...
               strcmp(paramStruct.variable_name, 'MOLAR_DOXY'))
            if (iscell(metaData.parametersList))
               metaData.parametersList{idP}.variable_name = '';
               metaData.parametersList{idP}.glider_original_parameter_name = '';
            else
               metaData.parametersList(idP).variable_name = '';
               metaData.parametersList(idP).glider_original_parameter_name = '';
            end
         end
      end
   end
end

% add meta-data to derived parameters
if (isfield(metaData, 'glider_parameter_derivation_data') && ...
      isfield(metaData.glider_parameter_derivation_data, 'DERIVATION_PARAMETER') && ...
      isfield(metaData.glider_parameter_derivation_data, 'DERIVATION_EQUATION') && ...
      isfield(metaData.glider_parameter_derivation_data, 'DERIVATION_COEFFICIENT') && ...
      isfield(metaData.glider_parameter_derivation_data, 'DERIVATION_COMMENT') && ...
      isfield(metaData.glider_parameter_derivation_data, 'DERIVATION_DATE'))
   if (~isempty(g_decGl_derivedParamMetaData))
      derivedParamNames = fields(g_decGl_derivedParamMetaData);
      derivationDataStruct = metaData.glider_parameter_derivation_data;
      for idP = 1:length(derivedParamNames)
         idF = find(strcmp(derivationDataStruct.DERIVATION_PARAMETER, derivedParamNames{idP}));
         if (~isempty(idF))
            if (gl_is_field_recursive(g_decGl_derivedParamMetaData, [derivedParamNames{idP} '.derivation_equation']))
               metaData.glider_parameter_derivation_data.DERIVATION_EQUATION{idF} = g_decGl_derivedParamMetaData.(derivedParamNames{idP}).derivation_equation;
            else
               metaData.glider_parameter_derivation_data.DERIVATION_EQUATION{idF} = '';
            end
            if (gl_is_field_recursive(g_decGl_derivedParamMetaData, [derivedParamNames{idP} '.derivation_coefficient']))
               metaData.glider_parameter_derivation_data.DERIVATION_COEFFICIENT{idF} = g_decGl_derivedParamMetaData.(derivedParamNames{idP}).derivation_coefficient;
            else
               metaData.glider_parameter_derivation_data.DERIVATION_COEFFICIENT{idF} = '';
            end
            if (gl_is_field_recursive(g_decGl_derivedParamMetaData, [derivedParamNames{idP} '.derivation_comment']))
               metaData.glider_parameter_derivation_data.DERIVATION_COMMENT{idF} = g_decGl_derivedParamMetaData.(derivedParamNames{idP}).derivation_comment;
            else
               metaData.glider_parameter_derivation_data.DERIVATION_COMMENT{idF} = '';
            end
            metaData.glider_parameter_derivation_data.DERIVATION_DATE{idF} = fileDate;
         end
      end
   end
end

% multi dimensional STRING information (TRANS_SYSTEM, TRANS_SYSTEM_ID,
% TRANS_FREQUENCY, POSITIONING_SYSTEM) are loaded in char array when possible
% (same size in second dimension)
struct1 = metaData;
fieldNames1 = fields(struct1);
for idF1 = 1:length(fieldNames1)
   struct2 = struct1.(fieldNames1{idF1});
   if (isstruct(struct2))
      fieldNames2 = fields(struct2);
      for idF2 = 1:length(fieldNames2)
         value = struct2.(fieldNames2{idF2});
         if (ischar(value) && (size(value, 1) > 1))
            value = cellstr(value)';
            metaData.(fieldNames1{idF1}).(fieldNames2{idF2}) = value;
         end
      end
   end
end

% BE CAREFUL: for slocum glider, we should not consider the case of the JSON
% links to EGO variable (i.e. glider parameter name specified in the JSON file
% may not have the same name in the .m file, the case may differ)
if (strcmpi(g_decGl_gliderType, 'slocum'))
   metaData.coordinate_variables = lower_var_name(metaData.coordinate_variables);
   metaData.parametersList = lower_var_name(metaData.parametersList);
end

% data to store in the NetCDF file
rawData = [];
rawData.rawData = a_rawDataStruct;
inputData = rawData;

% retrieve glider sensor information
tabSensor = metaData.glider_sensor_data.SENSOR;
tabSensorMaker = metaData.glider_sensor_data.SENSOR_MAKER;
tabSensorModel = metaData.glider_sensor_data.SENSOR_MODEL;
tabSensorSerialNumber = metaData.glider_sensor_data.SENSOR_SERIAL_NO;
tabSensorMount = metaData.glider_sensor_data.SENSOR_MOUNT;
if (isempty(tabSensorMount))
   tabSensorMount = cell(size(tabSensor));
end
tabSensorOrientation = metaData.glider_sensor_data.SENSOR_ORIENTATION;
if (isempty(tabSensorOrientation))
   tabSensorOrientation = cell(size(tabSensor));
end
nbSensor = length(tabSensor);

% retrieve glider parameter information
tabParameter = metaData.glider_parameter_data.PARAMETER;
tabParameterSensor = metaData.glider_parameter_data.PARAMETER_SENSOR;
tabParameterUnits = metaData.glider_parameter_data.PARAMETER_UNITS;
if (isempty(tabParameterUnits))
   tabParameterUnits = cell(size(tabParameter));
end
tabParameterAccuracy = metaData.glider_parameter_data.PARAMETER_ACCURACY;
if (isempty(tabParameterAccuracy))
   tabParameterAccuracy = cell(size(tabParameter));
end
tabParameterResolution = metaData.glider_parameter_data.PARAMETER_RESOLUTION;
if (isempty(tabParameterResolution))
   tabParameterResolution = cell(size(tabParameter));
end
nbParam = length(tabParameter);

% get meta-data dependent dimensions
[nbTransSystem] = gl_get_dim(metaData, 'glider_characteristics_data.TRANS_SYSTEM');
if (isempty(nbTransSystem))
   fprintf('WARNING: Cannot find %s in input data structure to compute the %s dimension\n', ...
      'glider_characteristics_data.TRANS_SYSTEM_ID', ...
      'N_TRANS_SYSTEM');
elseif (nbTransSystem == 0)
   nbTransSystem = 1;
   fprintf('INFO: Data pointed by %s is empty, %s dimension is set to 1\n', ...
      'glider_characteristics_data.TRANS_SYSTEM_ID', ...
      'N_TRANS_SYSTEM');
end
[nbPositioningSystem] = gl_get_dim(metaData, 'glider_characteristics_data.POSITIONING_SYSTEM');
if (isempty(nbPositioningSystem))
   fprintf('WARNING: Cannot find %s in input data structure to compute the %s dimension\n', ...
      'glider_characteristics_data.POSITIONING_SYSTEM', ...
      'N_POSITIONING_SYSTEM');
elseif (nbPositioningSystem == 0)
   nbPositioningSystem = 1;
   fprintf('INFO: Data pointed by %s is empty, %s dimension is set to 1\n', ...
      'glider_characteristics_data.POSITIONING_SYSTEM', ...
      'N_POSITIONING_SYSTEM');
end
[sizeTimeGps] = gl_get_dim(inputData, 'rawData.vars_time_gps.time');
if (isempty(sizeTimeGps))
   fprintf('WARNING: Cannot find %s in input data structure to compute the %s dimension\n', ...
      'rawData.vars_time_gps.time', ...
      'TIME_GPS');
elseif (sizeTimeGps == 0)
   sizeTimeGps = 1;
   fprintf('INFO: Data pointed by %s is empty, %s dimension is set to 1\n', ...
      'rawData.vars_time_gps.time', ...
      'TIME_GPS');
end
if (strcmpi(g_decGl_gliderType, 'slocum'))
   sizeTime = gl_get_dim(inputData, 'rawData.vars_m_time.m_present_time');
   if (isempty(sizeTime))
      sizeTime = gl_get_dim(inputData, 'rawData.vars_sci_time.sci_m_present_time');
   end
   if (isempty(sizeTime))
      fprintf('WARNING: Cannot find %s in input data structure to compute the %s dimension\n', ...
         'rawData.vars_sci_time.sci_m_present_time', ...
         'TIME');
   elseif (sizeTime == 0)
      sizeTime = 1;
      fprintf('INFO: Data pointed by %s is empty, %s dimension is set to 1\n', ...
         'rawData.vars_sci_time.sci_m_present_time', ...
         'TIME');
   end
elseif (strcmpi(g_decGl_gliderType, 'seaglider'))
   timeGliderVarName = g_decGl_gliderVarName{find(strcmp(g_decGl_egoVarName, 'TIME'))};
   sizeTime = gl_get_dim(inputData, ['rawData.vars_time.' timeGliderVarName]);
   if (isempty(sizeTime))
      fprintf('WARNING: Cannot find %s in input data structure to compute the %s dimension\n', ...
         'rawData.vars_time.time', ...
         'TIME');
   elseif (sizeTime == 0)
      sizeTime = 1;
      fprintf('INFO: Data pointed by %s is empty, %s dimension is set to 1\n', ...
         'rawData.vars_time.time', ...
         'TIME');
   end
elseif (strcmpi(g_decGl_gliderType, 'seaexplorer'))
   sizeTime = gl_get_dim(inputData, 'rawData.vars_m_time.Timestamp');
   if (isempty(sizeTime))
      sizeTime = gl_get_dim(inputData, 'rawData.vars_sci_time.PLD_REALTIMECLOCK');
   end
   if (isempty(sizeTime))
      fprintf('WARNING: Cannot find %s in input data structure to compute the %s dimension\n', ...
         'rawData.vars_sci_time.PLD_REALTIMECLOCK', ...
         'TIME');
   elseif (sizeTime == 0)
      sizeTime = 1;
      fprintf('INFO: Data pointed by %s is empty, %s dimension is set to 1\n', ...
         'rawData.vars_sci_time.PLD_REALTIMECLOCK', ...
         'TIME');
   end
end
% slocum sub-surface currents
if (~isempty(a_slocumCurrent))
   sizeTimeCurrent = length(a_slocumCurrent);
end
% seaglider sub-surface currents
if (isfield(a_rawDataStruct, 'vars_current') &&  ...
      isfield(a_rawDataStruct.vars_current, 'depth_avg_curr_qc') && ...
      ~isempty(a_rawDataStruct.vars_current.depth_avg_curr_qc) && ...
      isfield(metaData, 'current_estimate')) % to be sure the EGO 1.5 format is expected
   sizeTimeCurrent = length(a_rawDataStruct.vars_current.time);
end
% seaglider sub-surface currents
if (isfield(a_rawDataStruct, 'vars_current') &&  ...
      isfield(a_rawDataStruct.vars_current, 'surface_curr_qc') && ...
      ~isempty(a_rawDataStruct.vars_current.surface_curr_qc) && ...
      isfield(metaData, 'surf_current_estimate')) % to be sure the EGO 1.5 format is expected
   sizeTimeSurfCurrent = length(a_rawDataStruct.vars_current.timeGps);
end

% only one derivation can be set for the creation step
nbDerivation = 1;

% no history for the generation step
nbHistory = 1;
if (a_applyRtqc == 1)
   nbHistory = 3;
end

% create and open output NetCDF file
mode = netcdf.getConstant('NC_CLOBBER');
if (g_decGl_netCDFCompressionFlag)
   mode = bitor(mode, netcdf.getConstant('NETCDF4'));
   mode = bitor(mode, netcdf.getConstant('CLASSIC_MODEL'));
end
fCdf = netcdf.create(a_ncFileName, mode);
if (isempty(fCdf))
   fprintf('ERROR: Unable to create NetCDF output file: %s\n', a_ncFileName);
   return
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% DEFINE MODE BEGIN

if (VERBOSE_MODE == 1)
   fprintf('START DEFINE MODE\n');
end

% create dimensions
netcdf.defDim(fCdf, 'DATE_TIME', 14);
netcdf.defDim(fCdf, 'STRING4096', 4096);
netcdf.defDim(fCdf, 'STRING1024', 1024);
netcdf.defDim(fCdf, 'STRING256', 256);
netcdf.defDim(fCdf, 'STRING128', 128);
netcdf.defDim(fCdf, 'STRING64', 64);
netcdf.defDim(fCdf, 'STRING32', 32);
netcdf.defDim(fCdf, 'STRING16', 16);
netcdf.defDim(fCdf, 'STRING8', 8);
netcdf.defDim(fCdf, 'STRING4', 4);
netcdf.defDim(fCdf, 'STRING2', 2);

netcdf.defDim(fCdf, 'N_SENSOR', nbSensor);
netcdf.defDim(fCdf, 'N_PARAM', nbParam);
netcdf.defDim(fCdf, 'N_TRANS_SYSTEM', nbTransSystem);
netcdf.defDim(fCdf, 'N_POSITIONING_SYSTEM', nbPositioningSystem);
netcdf.defDim(fCdf, 'N_DERIVATION', nbDerivation);
netcdf.defDim(fCdf, 'N_HISTORY', nbHistory);

% timeDimId = netcdf.defDim(fCdf, 'TIME', netcdf.getConstant('NC_UNLIMITED'));
netcdf.defDim(fCdf, 'TIME', sizeTime);
netcdf.defDim(fCdf, 'TIME_GPS', sizeTimeGps);
% slocum sub-surface currents
if (~isempty(a_slocumCurrent))
   netcdf.defDim(fCdf, 'TIME_CURRENT', sizeTimeCurrent);
end
% seaglider sub-surface currents
if (isfield(a_rawDataStruct, 'vars_current') &&  ...
      isfield(a_rawDataStruct.vars_current, 'depth_avg_curr_qc') && ...
      ~isempty(a_rawDataStruct.vars_current.depth_avg_curr_qc) && ...
      isfield(metaData, 'current_estimate')) % to be sure the EGO 1.5 format is expected
   netcdf.defDim(fCdf, 'TIME_CURRENT', sizeTimeCurrent);
end
% seaglider sub-surface currents
if (isfield(a_rawDataStruct, 'vars_current') &&  ...
      isfield(a_rawDataStruct.vars_current, 'surface_curr_qc') && ...
      ~isempty(a_rawDataStruct.vars_current.surface_curr_qc) && ...
      isfield(metaData, 'surf_current_estimate')) % to be sure the EGO 1.5 format is expected
   netcdf.defDim(fCdf, 'TIME_SURF_CURRENT', sizeTimeSurfCurrent);
end

if (VERBOSE_MODE == 1)
   fprintf('N_SENSOR = %d\n', nbSensor);
   fprintf('N_PARAM = %d\n', nbParam);
   fprintf('N_TRANS_SYSTEM = %d\n', nbTransSystem);
   fprintf('N_POSITIONING_SYSTEM = %d\n', nbPositioningSystem);
   fprintf('N_DERIVATION = %d\n', nbDerivation);
   fprintf('N_HISTORY = %d\n', nbHistory);
   fprintf('TIME_GPS = %d\n', sizeTimeGps);
end

% arrays to store meta-data and data created variables
tabMetaVarName = [];
tabMetaVarId = [];
tabMetaVarInput = [];

tabDataVarName = [];
tabDataVarId = [];
tabDataVarInput = [];

% remove POSITION_QC from coordinate variables if LONGITUDE/LATITUDE is not
% present
egoVarNameList = [];
for idStruct = 1:length(metaData.coordinate_variables)
   if (iscell(metaData.coordinate_variables))
      varStruct = metaData.coordinate_variables{idStruct};
   else
      varStruct = metaData.coordinate_variables(idStruct);
   end
   egoVarNameList{idStruct} = varStruct.ego_variable_name;
end
if (isempty(find(strcmp(egoVarNameList, 'LATITUDE') == 1, 1)))
   idF = find(strcmp(egoVarNameList, 'POSITION_QC') == 1, 1);
   metaData.coordinate_variables(idF) = [];
end
% create coordinate variables
[fCdf, tabDataVarName, tabDataVarId, tabDataVarInput] = gl_create_nc_vars(fCdf, ...
   metaData.coordinate_variables, ...
   tabDataVarName, tabDataVarId, tabDataVarInput);

% create data variables
[fCdf, tabDataVarName, tabDataVarId, tabDataVarInput, adjVarList] = ...
   gl_create_nc_vars_with_qc(fCdf, ...
   metaData.parametersList, ...
   metaData.parameter_qc, ...
   metaData.parameter_adjusted_error, ...
   tabDataVarName, tabDataVarId, tabDataVarInput);

% create phase management variables
[fCdf, tabDataVarName, tabDataVarId, tabDataVarInput] = gl_create_nc_vars(fCdf, ...
   metaData.phase_management, ...
   tabDataVarName, tabDataVarId, tabDataVarInput);
if (g_decGl_addPhase2 == 1)
   [fCdf, tabDataVarName, tabDataVarId, tabDataVarInput] = gl_create_nc_vars(fCdf, ...
      metaData.phase_management2, ...
      tabDataVarName, tabDataVarId, tabDataVarInput);
end

% create positioning method variables
[fCdf, tabDataVarName, tabDataVarId, tabDataVarInput] = gl_create_nc_vars(fCdf, ...
   metaData.positioning_method, ...
   tabDataVarName, tabDataVarId, tabDataVarInput);

% create glider characteristics variables
[fCdf, tabMetaVarName, tabMetaVarId, tabMetaVarInput] = gl_create_nc_vars(fCdf, ...
   metaData.glider_characteristics_def, ...
   tabMetaVarName, tabMetaVarId, tabMetaVarInput);

% create glider deployment variables
[fCdf, tabMetaVarName, tabMetaVarId, tabMetaVarInput] = gl_create_nc_vars(fCdf, ...
   metaData.glider_deployment_def, ...
   tabMetaVarName, tabMetaVarId, tabMetaVarInput);

% create glider sensor variables
[fCdf, tabMetaVarName, tabMetaVarId, tabMetaVarInput] = gl_create_nc_vars(fCdf, ...
   metaData.glider_sensor_def, ...
   tabMetaVarName, tabMetaVarId, tabMetaVarInput);

% create glider parameter variables
[fCdf, tabMetaVarName, tabMetaVarId, tabMetaVarInput] = gl_create_nc_vars(fCdf, ...
   metaData.glider_parameter_def, ...
   tabMetaVarName, tabMetaVarId, tabMetaVarInput);

% create current estimate variables
% slocum sub-surface currents
if (~isempty(a_slocumCurrent))
   [fCdf, tabDataVarName, tabDataVarId, tabDataVarInput] = gl_create_nc_vars(fCdf, ...
      metaData.current_estimate, ...
      tabDataVarName, tabDataVarId, tabDataVarInput);
end
% seaglider sub-surface currents
if (isfield(a_rawDataStruct, 'vars_current') &&  ...
      isfield(a_rawDataStruct.vars_current, 'depth_avg_curr_qc') && ...
      ~isempty(a_rawDataStruct.vars_current.depth_avg_curr_qc) && ...
      isfield(metaData, 'current_estimate')) % to be sure the EGO 1.5 format is expected
   [fCdf, tabDataVarName, tabDataVarId, tabDataVarInput] = gl_create_nc_vars(fCdf, ...
      metaData.current_estimate, ...
      tabDataVarName, tabDataVarId, tabDataVarInput);
end
% seaglider sub-surface currents
if (isfield(a_rawDataStruct, 'vars_current') &&  ...
      isfield(a_rawDataStruct.vars_current, 'surface_curr_qc') && ...
      ~isempty(a_rawDataStruct.vars_current.surface_curr_qc) && ...
      isfield(metaData, 'surf_current_estimate')) % to be sure the EGO 1.5 format is expected
   [fCdf, tabDataVarName, tabDataVarId, tabDataVarInput] = gl_create_nc_vars(fCdf, ...
      metaData.surf_current_estimate, ...
      tabDataVarName, tabDataVarId, tabDataVarInput);
end

% create glider parameter derivation and calibration variables
[fCdf, tabMetaVarName, tabMetaVarId, tabMetaVarInput] = gl_create_nc_vars(fCdf, ...
   metaData.glider_parameter_derivation_def, ...
   tabMetaVarName, tabMetaVarId, tabMetaVarInput);

% create history variables
[fCdf, tabMetaVarName, tabMetaVarId, tabMetaVarInput] = gl_create_nc_vars(fCdf, ...
   metaData.history, ...
   tabMetaVarName, tabMetaVarId, tabMetaVarInput);

% create global attributes
[fCdf] = gl_create_nc_global_atts(fCdf, ...
   metaData.global_attributes, ...
   tabDataVarName, tabDataVarInput, inputData, currentDate, adjVarList);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% DEFINE MODE END

if (VERBOSE_MODE == 1)
   fprintf('STOP DEFINE MODE\n');
end

netcdf.endDef(fCdf);

% fill meta-data variables
for idVar = 1:length(tabMetaVarName)
   varInput = char(tabMetaVarInput{idVar});
   if (~isempty(varInput))
      [fieldExists, varData] = gl_check_field(metaData, varInput);

      if (fieldExists == 1)
         if (~isempty(varData))
            
            % modify PARAMETER_DATA_MODE for prameters with adjusted values
            if (strcmp(tabMetaVarName{idVar}, 'PARAMETER_DATA_MODE'))
               if (~isempty(adjVarList))
                  idF = find(strcmp(tabMetaVarName, 'PARAMETER'));
                  paramVarInput = char(tabMetaVarInput{idF});
                  [~, parameterList] = gl_check_field(metaData, paramVarInput);
                  for idVarAdj = 1:length(adjVarList)
                     adjVarName = adjVarList{idVarAdj};
                     idF = find(strcmp(adjVarName, parameterList));
                     if (iscell(varData))
                        varData{idF} = 'A';
                     else
                        varData(idF) = 'A';
                     end
                  end
               end
               if (g_decGl_hrDataFlag == 1)
                  varData = repmat({'P'}, size(varData));
               end
            end
            
            [varname, xtype, dimids, natts] = netcdf.inqVar(fCdf, tabMetaVarId{idVar});
            if (isempty(dimids))
               if (~isempty(varData))
                  value = varData;
                  if (iscell(value))
                     value = char(value);
                  end
                  netcdf.putVar(fCdf, tabMetaVarId{idVar}, value);
               end
            elseif (length(dimids) == 1)
               if (~isempty(varData))
                  value = varData;
                  if (iscell(value))
                     value = char(value);
                  end
                  netcdf.putVar(fCdf, tabMetaVarId{idVar}, 0, length(value), value);
               end
            elseif (length(dimids) == 2)
               if (iscell(varData))
                  for id = 1:length(varData)
                     valueStr = char(varData{id});
                     if (~isempty(valueStr))
                        netcdf.putVar(fCdf, tabMetaVarId{idVar}, fliplr([id-1 0]), fliplr([1 length(valueStr)]), valueStr');
                     end
                  end
               elseif (size(varData, 1) > 1)
                  for id = 1:size(varData, 1)
                     valueStr = varData(id, :);
                     if (~isempty(valueStr))
                        netcdf.putVar(fCdf, tabMetaVarId{idVar}, fliplr([id-1 0]), fliplr([1 length(valueStr)]), valueStr');
                     end
                  end
               elseif (ischar(varData))
                  if (~isempty(varData))
                     netcdf.putVar(fCdf, tabMetaVarId{idVar}, [0 0], fliplr([1 length(varData)]), varData);
                  end
               end
            elseif (length(dimids) == 3)
               % only for DERIVATION_* variables; as we do not manage more than
               % one derivation in the json deployment files => N_DERIVATION = 1
               if (iscell(varData))
                  for id = 1:length(varData)
                     valueStr = char(varData{id});
                     if (~isempty(valueStr))
                        netcdf.putVar(fCdf, tabMetaVarId{idVar}, fliplr([0 id-1 0]), fliplr([1 1 length(valueStr)]), valueStr');
                     end
                  end
               elseif (size(varData, 1) > 1)
                  for id = 1:size(varData, 1)
                     valueStr = varData(id, :);
                     if (~isempty(valueStr))
                        netcdf.putVar(fCdf, tabMetaVarId{idVar}, fliplr([0 id-1 0]), fliplr([1 1 length(valueStr)]), valueStr');
                     end
                  end
               elseif (ischar(varData))
                  if (~isempty(varData))
                     netcdf.putVar(fCdf, tabMetaVarId{idVar}, [0 0 0], fliplr([1 1 length(varData)]), varData);
                  end
               end
            else
               fprintf('ERROR: Don''t know how to manage %d dimension variable (for ''%s'')\n', ...
                  length(dimids), char(tabMetaVarName{idVar}));
            end
         end
         %       else
         %          fprintf('WARNING: Cannot find input data structure %s to get %s data\n', ...
         %             varInput, char(tabMetaVarName{idVar}));
      end
   end
end

% some variables have been computed and added by the decoder (g_decGl_directEgoVarPathName)
% add them to the list
for idV = 1:length(g_decGl_directEgoVarPathName)
   varNameOri = ['rawData.' g_decGl_directEgoVarPathName{idV}];
   sep = strfind(varNameOri, '.');
   varName = varNameOri(sep(end)+1:end);
   idF = find(strcmp(tabDataVarName, varName) == 1, 1);
   if (~isempty(idF))
      tabDataVarInput{idF} = varNameOri;
   else
      if (gl_var_is_present(fCdf, varName))
         tabDataVarName{end+1} = varName;
         tabDataVarInput{end+1} = varNameOri;
         tabDataVarId{end+1} = netcdf.inqVarID(fCdf, varName);
      else
         fprintf('WARNING: cannot add %s data to the EGO file\n', ...
            varName);
      end
   end
end

% add current estimate data
% slocum sub-surface currents
if (~isempty(a_slocumCurrent))
   current_estimate = [];
   fieldNameList = [{'time'} {'lat'} {'lon'} {'mean_depth'} {'water_vx'} {'water_vy'}];
   for idV = 1:length(fieldNameList)
      fName = fieldNameList{idV};
      switch (fName)
         case 'time'
            epochTime = gl_julian_2_epoch([a_slocumCurrent.time]);
            current_estimate.time = epochTime;
            idF = find(strcmp('WATERCURRENTS_TIME', tabDataVarName));
            tabDataVarInput{idF} = 'current_estimate.time';
         case 'lat'
            current_estimate.lat = [a_slocumCurrent.lat];
            idF = find(strcmp('WATERCURRENTS_LATITUDE', tabDataVarName));
            tabDataVarInput{idF} = 'current_estimate.lat';
         case 'lon'
            current_estimate.lon = [a_slocumCurrent.lon];
            idF = find(strcmp('WATERCURRENTS_LONGITUDE', tabDataVarName));
            tabDataVarInput{idF} = 'current_estimate.lon';
         case 'mean_depth'
            current_estimate.depth = [a_slocumCurrent.mean_depth];
            idF = find(strcmp('WATERCURRENTS_DEPTH', tabDataVarName));
            tabDataVarInput{idF} = 'current_estimate.depth';
         case 'water_vx'
            current_estimate.u = [a_slocumCurrent.water_vx]*100;
            idF = find(strcmp('WATERCURRENTS_U', tabDataVarName));
            tabDataVarInput{idF} = 'current_estimate.u';
         case 'water_vy'
            current_estimate.v = [a_slocumCurrent.water_vy]*100;
            idF = find(strcmp('WATERCURRENTS_V', tabDataVarName));
            tabDataVarInput{idF} = 'current_estimate.v';
      end
   end
   inputData.current_estimate = current_estimate;
end
% seaglider sub-surface currents
if (isfield(a_rawDataStruct, 'vars_current') &&  ...
      isfield(a_rawDataStruct.vars_current, 'depth_avg_curr_qc') && ...
      ~isempty(a_rawDataStruct.vars_current.depth_avg_curr_qc) && ...
      isfield(metaData, 'current_estimate')) % to be sure the EGO 1.5 format is expected
   % sub-surface currents
   current_estimate = [];
   fieldNameList = [{'time'} {'latitude'} {'longitude'} {'meanDepth'} ...
      {'depth_avg_curr_east'} {'depth_avg_curr_east_gsm'} ...
      {'depth_avg_curr_north'} {'depth_avg_curr_north_gsm'} ...
      {'depth_avg_curr_error'} {'depth_avg_curr_qc'}];
   for idV = 1:length(fieldNameList)
      fName = fieldNameList{idV};
      switch (fName)
         case 'time'
            if (isfield(a_rawDataStruct.vars_current, 'time'))
               current_estimate.time = a_rawDataStruct.vars_current.time;
               idF = find(strcmp('WATERCURRENTS_TIME', tabDataVarName));
               tabDataVarInput{idF} = 'current_estimate.time';
            end
         case 'latitude'
            if (isfield(a_rawDataStruct.vars_current, 'latitude'))
               current_estimate.lat = a_rawDataStruct.vars_current.latitude;
               idF = find(strcmp('WATERCURRENTS_LATITUDE', tabDataVarName));
               tabDataVarInput{idF} = 'current_estimate.lat';
            end
         case 'longitude'
            if (isfield(a_rawDataStruct.vars_current, 'longitude'))
               current_estimate.lon = a_rawDataStruct.vars_current.longitude;
               idF = find(strcmp('WATERCURRENTS_LONGITUDE', tabDataVarName));
               tabDataVarInput{idF} = 'current_estimate.lon';
            end
         case 'meanDepth'
            if (isfield(a_rawDataStruct.vars_current, 'meanDepth'))
               current_estimate.depth = a_rawDataStruct.vars_current.meanDepth;
               idF = find(strcmp('WATERCURRENTS_DEPTH', tabDataVarName));
               tabDataVarInput{idF} = 'current_estimate.depth';
            end
         case 'depth_avg_curr_east'
            if (isfield(a_rawDataStruct.vars_current, 'depth_avg_curr_east'))
               current_estimate.u = a_rawDataStruct.vars_current.depth_avg_curr_east;
               idF = find(strcmp('WATERCURRENTS_U', tabDataVarName));
               tabDataVarInput{idF} = 'current_estimate.u';
            end
         case 'depth_avg_curr_east_gsm'
            if (~isfield(a_rawDataStruct.vars_current, 'depth_avg_curr_east'))
               if (isfield(a_rawDataStruct.vars_current, 'depth_avg_curr_east_gsm'))
                  current_estimate.u = a_rawDataStruct.vars_current.depth_avg_curr_east_gsm;
                  idF = find(strcmp('WATERCURRENTS_U', tabDataVarName));
                  tabDataVarInput{idF} = 'current_estimate.u';
               end
            end
         case 'depth_avg_curr_north'
            if (isfield(a_rawDataStruct.vars_current, 'depth_avg_curr_north'))
               current_estimate.v = a_rawDataStruct.vars_current.depth_avg_curr_north;
               idF = find(strcmp('WATERCURRENTS_V', tabDataVarName));
               tabDataVarInput{idF} = 'current_estimate.v';
            end
         case 'depth_avg_curr_north_gsm'
            if (~isfield(a_rawDataStruct.vars_current, 'depth_avg_curr_north'))
               if (isfield(a_rawDataStruct.vars_current, 'depth_avg_curr_north_gsm'))
                  current_estimate.v = a_rawDataStruct.vars_current.depth_avg_curr_north_gsm;
                  idF = find(strcmp('WATERCURRENTS_V', tabDataVarName));
                  tabDataVarInput{idF} = 'current_estimate.v';
               end
            end
         case 'depth_avg_curr_error'
            if (isfield(a_rawDataStruct.vars_current, 'depth_avg_curr_error'))
               current_estimate.err = a_rawDataStruct.vars_current.depth_avg_curr_error;
               idF = find(strcmp('WATERCURRENTS_ERROR', tabDataVarName));
               tabDataVarInput{idF} = 'current_estimate.err';
            end
         case 'depth_avg_curr_qc'
            if (isfield(a_rawDataStruct.vars_current, 'depth_avg_curr_qc'))
               current_estimate.qc = a_rawDataStruct.vars_current.depth_avg_curr_qc;
               idF = find(strcmp('WATERCURRENTS_QC', tabDataVarName));
               tabDataVarInput{idF} = 'current_estimate.qc';
            end
      end
   end
   inputData.current_estimate = current_estimate;
end
% seaglider sub-surface currents
if (isfield(a_rawDataStruct, 'vars_current') &&  ...
      isfield(a_rawDataStruct.vars_current, 'surface_curr_qc') && ...
      ~isempty(a_rawDataStruct.vars_current.surface_curr_qc) && ...
      isfield(metaData, 'surf_current_estimate')) % to be sure the EGO 1.5 format is expected
   % surface currents
   surf_current_estimate = [];
   fieldNameList = [{'timeGps'} {'latitudeGps'} {'longitudeGps'} ...
      {'surface_curr_east'} {'surface_curr_north'} ...
      {'surface_curr_error'} {'surface_curr_qc'}];
   for idV = 1:length(fieldNameList)
      fName = fieldNameList{idV};
      switch (fName)
         case 'timeGps'
            if (isfield(a_rawDataStruct.vars_current, 'timeGps'))
               surf_current_estimate.time = a_rawDataStruct.vars_current.timeGps;
               idF = find(strcmp('SURF_WATERCURRENTS_TIME', tabDataVarName));
               tabDataVarInput{idF} = 'surf_current_estimate.time';
            end
         case 'latitudeGps'
            if (isfield(a_rawDataStruct.vars_current, 'latitudeGps'))
               surf_current_estimate.lat = a_rawDataStruct.vars_current.latitudeGps;
               idF = find(strcmp('SURF_WATERCURRENTS_LATITUDE', tabDataVarName));
               tabDataVarInput{idF} = 'surf_current_estimate.lat';
            end
         case 'longitudeGps'
            if (isfield(a_rawDataStruct.vars_current, 'longitudeGps'))
               surf_current_estimate.lon = a_rawDataStruct.vars_current.longitudeGps;
               idF = find(strcmp('SURF_WATERCURRENTS_LONGITUDE', tabDataVarName));
               tabDataVarInput{idF} = 'surf_current_estimate.lon';
            end
         case 'surface_curr_east'
            if (isfield(a_rawDataStruct.vars_current, 'surface_curr_east'))
               surf_current_estimate.u = a_rawDataStruct.vars_current.surface_curr_east;
               idF = find(strcmp('SURF_WATERCURRENTS_U', tabDataVarName));
               tabDataVarInput{idF} = 'surf_current_estimate.u';
            end
         case 'surface_curr_north'
            if (isfield(a_rawDataStruct.vars_current, 'surface_curr_north'))
               surf_current_estimate.v = a_rawDataStruct.vars_current.surface_curr_north;
               idF = find(strcmp('SURF_WATERCURRENTS_V', tabDataVarName));
               tabDataVarInput{idF} = 'surf_current_estimate.v';
            end
         case 'surface_curr_error'
            if (isfield(a_rawDataStruct.vars_current, 'surface_curr_error'))
               surf_current_estimate.err = a_rawDataStruct.vars_current.surface_curr_error;
               idF = find(strcmp('SURF_WATERCURRENTS_ERROR', tabDataVarName));
               tabDataVarInput{idF} = 'surf_current_estimate.err';
            end
         case 'surface_curr_qc'
            if (isfield(a_rawDataStruct.vars_current, 'surface_curr_qc'))
               surf_current_estimate.qc = a_rawDataStruct.vars_current.surface_curr_qc;
               idF = find(strcmp('SURF_WATERCURRENTS_QC', tabDataVarName));
               tabDataVarInput{idF} = 'surf_current_estimate.qc';
            end
      end
   end
   inputData.surf_current_estimate = surf_current_estimate;
end

% fill data variables
for idVar = 1:length(tabDataVarName)
   varInput = tabDataVarInput{idVar};
   putData = 0;
   if (~isempty(varInput))
      [fieldExists, varData] = gl_check_field(inputData, varInput);
      if (fieldExists == 1)
         if (~isempty(varData))
            idNan = find(isnan(varData));
            if (~isempty(idNan))
               fillVal = netcdf.getAtt(fCdf, tabDataVarId{idVar}, '_FillValue');
               varData(idNan) = fillVal;
            end
            netcdf.putVar(fCdf, tabDataVarId{idVar}, 0, length(varData), varData);
            putData = 1;
         end
         %       else
         %          fprintf('WARNING: Cannot find input data structure %s to get %s data\n', ...
         %             varInput, char(tabDataVarName{idVar}));
      end
      
      % fill QC data variables
      if (gl_var_is_present(fCdf, [tabDataVarName{idVar} '_QC']))
         [fieldExists, varData] = gl_check_field(inputData, [varInput '_qc']);
         if (fieldExists == 1)
            if (~isempty(varData))
               varData(find(varData == 0)) = nan; % input ' ' converted to FillValue
               varData = varData - 48; % input in char output in byte
               varData(find(varData == 6)) = nan; % input QC_UNSAMPLED converted to FillValue
               qcVarId = netcdf.inqVarID(fCdf, [tabDataVarName{idVar} '_QC']);
               idNan = find(isnan(varData));
               if (~isempty(idNan))
                  fillVal = netcdf.getAtt(fCdf, qcVarId, '_FillValue');
                  varData(idNan) = fillVal;
               end
               netcdf.putVar(fCdf, qcVarId, 0, length(varData), int8(varData));
            end
         end
      end
   end
   if (putData == 0)
      [varName, ~, ~, ~] = netcdf.inqVar(fCdf, tabDataVarId{idVar});
      if (~isempty(find(strcmp(varName, 'TIME') == 1)))
         fillVal = netcdf.getAtt(fCdf, tabDataVarId{idVar}, '_FillValue');
         netcdf.putVar(fCdf, tabDataVarId{idVar}, 0, 1, fillVal);
         
         fprintf('INFO: Data pointed by %s is empty, %s dimension is set to 1\n', ...
            varInput, ...
            'TIME');
      end
   end
end

% fill empty <PARAM>_QC variables with '0' when <PARAM> ~= FillValue
[nbDims, nbVars, nbGAtts, unlimId] = netcdf.inq(fCdf);
for idVar = 0:nbVars-1
   [varNameQc, varType, varDims, nbAtts] = netcdf.inqVar(fCdf, idVar);
   if ((length(varNameQc) > 3) && strcmp(varNameQc(end-2:end), '_QC'))
      fillVal = netcdf.getAtt(fCdf, idVar, '_FillValue');
      dataQc = netcdf.getVar(fCdf, idVar);
      uDataQc = unique(dataQc);
      if ((length(uDataQc) == 1) && (uDataQc == fillVal))
         varName = varNameQc(1:end-3);
         if (gl_var_is_present(fCdf, varName))
            varId = netcdf.inqVarID(fCdf, varName);
            fillVal = netcdf.getAtt(fCdf, varId, '_FillValue');
            data = netcdf.getVar(fCdf, varId);
            dataQc(find(data ~= fillVal)) = g_decGl_qcNoQc;
            %             dataQc(find(data == fillVal)) = g_decGl_qcMissing;
            netcdf.putVar(fCdf, idVar, dataQc);
         elseif (strcmp(varName, 'POSITION'))
            if (gl_var_is_present(fCdf, 'LATITUDE'))
               varName = 'LATITUDE';
               varId = netcdf.inqVarID(fCdf, varName);
               fillVal = netcdf.getAtt(fCdf, varId, '_FillValue');
               data = netcdf.getVar(fCdf, varId);
               dataQc(find(data ~= fillVal)) = g_decGl_qcNoQc;
               %                dataQc(find(data == fillVal)) = g_decGl_qcMissing;
               netcdf.putVar(fCdf, idVar, dataQc);
            end
         elseif (strcmp(varName, 'POSITION_GPS'))
            if (gl_var_is_present(fCdf, 'LATITUDE_GPS'))
               varName = 'LATITUDE_GPS';
               varId = netcdf.inqVarID(fCdf, varName);
               fillVal = netcdf.getAtt(fCdf, varId, '_FillValue');
               data = netcdf.getVar(fCdf, varId);
               dataQc(find(data ~= fillVal)) = g_decGl_qcNoQc;
%                dataQc(find(data == fillVal)) = g_decGl_qcMissing;
               netcdf.putVar(fCdf, idVar, dataQc);
            end
         end
      end
   end
end

% fill historical information
value = 'IF';
netcdf.putVar(fCdf, netcdf.inqVarID(fCdf, 'HISTORY_INSTITUTION'), ...
   fliplr([0 0]), fliplr([1 length(value)]), value');
value = 'ARFM';
netcdf.putVar(fCdf, netcdf.inqVarID(fCdf, 'HISTORY_STEP'), ...
   fliplr([0 0]), fliplr([1 length(value)]), value');
value = 'CODG';
netcdf.putVar(fCdf, netcdf.inqVarID(fCdf, 'HISTORY_SOFTWARE'), ...
   fliplr([0 0]), fliplr([1 length(value)]), value');
value = g_decGl_decoderVersion;
netcdf.putVar(fCdf, netcdf.inqVarID(fCdf, 'HISTORY_SOFTWARE_RELEASE'), ...
   fliplr([0 0]), fliplr([1 length(value)]), value');
netcdf.putVar(fCdf, netcdf.inqVarID(fCdf, 'HISTORY_DATE'), ...
   fliplr([0 0]), fliplr([1 length(fileDate)]), fileDate');

netcdf.close(fCdf);

if (g_decGl_realtimeFlag == 1)
   % store information for the XML report
   g_decGl_reportStruct.outputFiles = [g_decGl_reportStruct.outputFiles ...
      {a_ncFileName}];
end

if (VERBOSE_MODE == 1)
   fprintf('... NetCDF file created\n');
end

o_ok = 1;

return

% ------------------------------------------------------------------------------
% Set in lower case glider coordinate variable names.
%
% SYNTAX :
%  [o_struct] = lower_var_name(a_struct)
%
% INPUT PARAMETERS :
%   a_struct : input struct
%
% OUTPUT PARAMETERS :
%   o_struct : output struct
%
% EXAMPLES :
%
% SEE ALSO :
% AUTHOR : Jean-Philippe Rannou (Capgemini) (jean.philippe.rannou@partenaire-exterieur.ifremer.fr)
% ------------------------------------------------------------------------------
% RELEASES :
%   02/20/2018 - RNU - creation
% ------------------------------------------------------------------------------
function [o_struct] = lower_var_name(a_struct)

% output data initialization
o_struct = a_struct;

for idStruct = 1:length(o_struct)
   if (iscell(o_struct))
      varStruct = o_struct{idStruct};
   else
      varStruct = o_struct(idStruct);
   end
   
   inputVar = varStruct.variable_name;
   
   idF = strfind(inputVar, '.');
   if (~isempty(idF))
      
      %       if (~strcmp(inputVar(idF(end)+1:end), lower(inputVar(idF(end)+1:end))))
      %          a=1
      %       end
      
      inputVar = [inputVar(1:idF(end)) lower(inputVar(idF(end)+1:end))];
   end
   
   if (iscell(o_struct))
      o_struct{idStruct}.variable_name = inputVar;
   else
      o_struct(idStruct).variable_name = inputVar;
   end
end

return
