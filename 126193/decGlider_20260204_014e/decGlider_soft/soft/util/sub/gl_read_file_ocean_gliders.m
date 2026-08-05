% ------------------------------------------------------------------------------
% Read a NetCDF OceanGliders file contents.
%
% SYNTAX :
% [o_dimensions, o_globalAttributes, o_trajNameData, o_platformInfoData, ...
%  o_deployInfoData, o_fieldComparisonInfoData, o_hardwareInfoData, ...
%  o_telecomInfoData, o_sensorInfoData, o_paramData] = ...
%  gl_read_file_ocean_gliders(a_inputPathFileName)
%
% INPUT PARAMETERS :
%   a_inputPathFileName : OceanGliders file path name
%
% OUTPUT PARAMETERS :
%   o_dimensions              : dimension data
%   o_globalAttributes        : global attribute data
%   o_trajNameData            : trajectory name data
%   o_platformInfoData        : platform information data
%   o_deployInfoData          : deployment information data
%   o_fieldComparisonInfoData : field comparison information data
%   o_hardwareInfoData        : hardware information data
%   o_telecomInfoData         : telecom information data
%   o_sensorInfoData          : sensor information data
%   o_paramData               : parameter measurements data
%
% EXAMPLES :
%
% SEE ALSO :
% AUTHOR : Jean-Philippe Rannou (Capgemini) (jean.philippe.rannou@partenaire-exterieur.ifremer.fr)
% ------------------------------------------------------------------------------
% RELEASES :
%   02/11/2025 - RNU - creation
% ------------------------------------------------------------------------------
function [o_dimensions, o_globalAttributes, o_trajNameData, o_platformInfoData, ...
   o_deployInfoData, o_fieldComparisonInfoData, o_hardwareInfoData, ...
   o_telecomInfoData, o_sensorInfoData, o_paramData] = ...
   gl_read_file_ocean_gliders(a_inputPathFileName)

o_dimensions = [];
o_globalAttributes = [];
o_trajNameData = [];
o_platformInfoData = [];
o_deployInfoData = [];
o_fieldComparisonInfoData = [];
o_hardwareInfoData = [];
o_telecomInfoData = [];
o_sensorInfoData = [];
o_paramData = [];

% check the NetCDF file
if ~(exist(a_inputPathFileName, 'file') == 2)
   fprintf('File not found : %s\n', a_inputPathFileName);
   return
end

% open NetCDF file
fCdf = netcdf.open(a_inputPathFileName, 'NC_NOWRITE');
if (isempty(fCdf))
   fprintf('ERROR: Unable to open NetCDF input file: %s\n', a_inputPathFileName);
   return
end

% retrieve dimensions
dimList = [ ...
   {'N_MEASUREMENTS'} ...
   ];
for id = 1:length(dimList)
   name = dimList{id};
   if (gl_dim_is_present(fCdf, name))
      [~, value] = netcdf.inqDim(fCdf, netcdf.inqDimID(fCdf, name));
      o_dimensions = [o_dimensions {name} {value}];
   else
      o_dimensions = [o_dimensions {name} {[]}];
   end
end

% retrieve global attributes
[nbDims, nbVars, nbGAtts, unlimId] = netcdf.inq(fCdf);
for id = 0:nbGAtts-1
   name = netcdf.inqAttName(fCdf, netcdf.getConstant('NC_GLOBAL'), id);
   value = netcdf.getAtt(fCdf, netcdf.getConstant('NC_GLOBAL'), name);
   o_globalAttributes = [o_globalAttributes {name} {value}];
end

% retrieve trajectory name data
trajNameList = [ ...
   {'TRAJECTORY'} ...
   ];
for id = 1:length(trajNameList)
   name = trajNameList{id};
   if (gl_var_is_present(fCdf, name))
      value = netcdf.getVar(fCdf, netcdf.inqVarID(fCdf, name));
      o_trajNameData = [o_trajNameData {name} {value}];
   else
      o_trajNameData = [o_trajNameData {name} {[]}];
   end
end

% retrieve platform information data
platformInfoList = [ ...
   {'WMO_IDENTIFIER'} ...
   {'PLATFORM_MODEL'} ...
   {'PLATFORM_SERIAL_NUMBER'} ...
   {'PLATFORM_NAME'} ...
   {'PLATFORM_DEPTH_RATING'} ...
   {'ICES_CODE'} ...
   {'PLATFORM_MAKER'} ...
   ];
for id = 1:length(platformInfoList)
   name = platformInfoList{id};
   if (gl_var_is_present(fCdf, name))
      value = netcdf.getVar(fCdf, netcdf.inqVarID(fCdf, name));
      o_platformInfoData = [o_platformInfoData {name} {value}];
   else
      o_platformInfoData = [o_platformInfoData {name} {[]}];
   end
end

% retrieve deployment information data
deployInfoList = [ ...
   {'DEPLOYMENT_TIME'} ...
   {'DEPLOYMENT_LATITUDE'} ...
   {'DEPLOYMENT_LONGITUDE'} ...
   ];
for id = 1:length(deployInfoList)
   name = deployInfoList{id};
   if (gl_var_is_present(fCdf, name))
      value = netcdf.getVar(fCdf, netcdf.inqVarID(fCdf, name));
      o_deployInfoData = [o_deployInfoData {name} {value}];
   else
      o_deployInfoData = [o_deployInfoData {name} {[]}];
   end
end

% retrieve field comparison information data
fieldComparisonInfoList = [ ...
   {'FIELD_COMPARISON_REFERENCE'} ...
   ];
for id = 1:length(fieldComparisonInfoList)
   name = fieldComparisonInfoList{id};
   if (gl_var_is_present(fCdf, name))
      value = netcdf.getVar(fCdf, netcdf.inqVarID(fCdf, name));
      o_fieldComparisonInfoData = [o_fieldComparisonInfoData {name} {value}];
   else
      o_fieldComparisonInfoData = [o_fieldComparisonInfoData {name} {[]}];
   end
end

% retrieve hardware information data
hardwareInfoList = [ ...
   {'GLIDER_FIRMWARE_VERSION'} ...
   {'LANDSTATION_VERSION'} ...
   {'BATTERY_TYPE'} ...
   {'BATTERY_PACK'} ...
   ];
for id = 1:length(hardwareInfoList)
   name = hardwareInfoList{id};
   if (gl_var_is_present(fCdf, name))
      value = netcdf.getVar(fCdf, netcdf.inqVarID(fCdf, name));
      o_hardwareInfoData = [o_hardwareInfoData {name} {value}];
   else
      o_hardwareInfoData = [o_hardwareInfoData {name} {[]}];
   end
end

% retrieve telecom information data
telecomInfoList = [ ...
   {'TELECOM_TYPE'} ...
   {'TRACKING_SYSTEM'} ...
   ];
for id = 1:length(telecomInfoList)
   name = telecomInfoList{id};
   if (gl_var_is_present(fCdf, name))
      value = netcdf.getVar(fCdf, netcdf.inqVarID(fCdf, name));
      o_telecomInfoData = [o_telecomInfoData {name} {value}];
   else
      o_telecomInfoData = [o_telecomInfoData {name} {[]}];
   end
end

% retrieve the list of SENSOR_* variables
sensorName = [];
for idVar = 0:nbVars-1
   [varName, varType, varDims, nbAtts] = netcdf.inqVar(fCdf, idVar);
   if (strncmp(varName, 'SENSOR_', length('SENSOR_')))
      sensorName{end+1} = varName;
   end
end
% retrieve associated attributes
sensorTypeVoc = repmat({''}, size(sensorName));
sensorLongName = repmat({''}, size(sensorName));
sensorSensorModel = repmat({''}, size(sensorName));
sensorSensorModelVoc = repmat({''}, size(sensorName));
sensorSensorMaker = repmat({''}, size(sensorName));
sensorSensorMakerVoc = repmat({''}, size(sensorName));
sensorSensorSerialNo = repmat({''}, size(sensorName));
sensorSensorCalbDate = repmat({''}, size(sensorName));
for idSensor = 1:length(sensorName)
   sensorTypeVoc{idSensor} = netcdf.getAtt(fCdf, netcdf.inqVarID(fCdf, sensorName{idSensor}), 'sensor_type_vocabulary');
   sensorLongName{idSensor} = netcdf.getAtt(fCdf, netcdf.inqVarID(fCdf, sensorName{idSensor}), 'long_name');
   sensorSensorModel{idSensor} = netcdf.getAtt(fCdf, netcdf.inqVarID(fCdf, sensorName{idSensor}), 'sensor_model');
   sensorSensorModelVoc{idSensor} = netcdf.getAtt(fCdf, netcdf.inqVarID(fCdf, sensorName{idSensor}), 'sensor_model_vocabulary');
   sensorSensorMaker{idSensor} = netcdf.getAtt(fCdf, netcdf.inqVarID(fCdf, sensorName{idSensor}), 'sensor_maker');
   sensorSensorMakerVoc{idSensor} = netcdf.getAtt(fCdf, netcdf.inqVarID(fCdf, sensorName{idSensor}), 'sensor_maker_vocabulary');
   sensorSensorSerialNo{idSensor} = netcdf.getAtt(fCdf, netcdf.inqVarID(fCdf, sensorName{idSensor}), 'sensor_serial_number');
   sensorSensorCalbDate{idSensor} = netcdf.getAtt(fCdf, netcdf.inqVarID(fCdf, sensorName{idSensor}), 'sensor_calibration_date');
end
o_sensorInfoData.sensorName = sensorName;
o_sensorInfoData.sensorTypeVoc = sensorTypeVoc;
o_sensorInfoData.sensorLongName = sensorLongName;
o_sensorInfoData.sensorSensorModel = sensorSensorModel;
o_sensorInfoData.sensorSensorModelVoc = sensorSensorModelVoc;
o_sensorInfoData.sensorSensorMaker = sensorSensorMaker;
o_sensorInfoData.sensorSensorMakerVoc = sensorSensorMakerVoc;
o_sensorInfoData.sensorSensorSerialNo = sensorSensorSerialNo;
o_sensorInfoData.sensorSensorCalbDate = sensorSensorCalbDate;

% retrieve the list of variables that have the N_MEASUREMENTS dimension
nMeasDimId = netcdf.inqDimID(fCdf, 'N_MEASUREMENTS');
paramNameList = [];
for idVar = 0:nbVars-1
   [varName, varType, varDims, nbAtts] = netcdf.inqVar(fCdf, idVar);
   if (sum(ismember(nMeasDimId, varDims)) > 0)
      paramNameList{end+1} = varName;
   end
end

% retrieve associated data
for idP = 1:length(paramNameList)
   value = netcdf.getVar(fCdf, netcdf.inqVarID(fCdf, paramNameList{idP}));
   o_paramData = [o_paramData {paramNameList{idP}} {value}];
end

netcdf.close(fCdf);

return
