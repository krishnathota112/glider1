% ------------------------------------------------------------------------------
% Generate OceanGliders NetCDF file from EGO NetCDF file.
%
% SYNTAX :
%  nc_ego_2_ocean_gliders_file(a_deployName, a_inputDirName, a_outputDirName)
%
% INPUT PARAMETERS :
%   a_deployName    : name of the deployment
%   a_inputDirName  : directory of the input EGO file
%   a_outputDirName : directory of the output OG file
%
% OUTPUT PARAMETERS :
%
% EXAMPLES :
%
% SEE ALSO :
% AUTHOR : Jean-Philippe Rannou (Capgemini) (jean.philippe.rannou@partenaire-exterieur.ifremer.fr)
% ------------------------------------------------------------------------------
% RELEASES :
%   02/04/2025 - RNU - creation
% ------------------------------------------------------------------------------
function nc_ego_2_ocean_gliders_file(a_deployName, a_inputDirName, a_outputDirName)

ncFiles = dir([a_inputDirName '/' a_deployName '_*.nc']);
for idF = 1:length(ncFiles)
   ncInputFileName = ncFiles(idF).name;
   [~, name, ext] = fileparts(ncInputFileName);
   inputFilePathName = [a_inputDirName '/' name ext];

   % convert EGO data into OG data
   [ogGlobalAtt, ogTrajName, ogPlatformInfo, ogDeployInfo, ...
      ogFieldCompRef, ogHardwareInfo, ogTelecomInfo, ...
      ogParamList, ogSensorList, ogParamData] = ego_2_og_mapping(inputFilePathName);

   if (~isempty(ogPlatformInfo.PLATFORM_SERIAL_NUMBER))
      if (~isempty(ogGlobalAtt.start_date))
         idF = strfind(name, '_');
         dataMode = name(idF(end)+1:end);
         ncOutputFileName = [ogPlatformInfo.PLATFORM_SERIAL_NUMBER '_' ogGlobalAtt.start_date '_' dataMode];
         ogGlobalAtt.id = ncOutputFileName;
         ogTrajName.TRAJECTORY = [ogPlatformInfo.PLATFORM_SERIAL_NUMBER '_' ogGlobalAtt.start_date];
         outFilePathName = [a_outputDirName '/' ncOutputFileName '.nc'];
      else
         fprintf('ERROR: start_date is empty - OG file not generated\n');
         continue
      end
   else
      fprintf('ERROR: PLATFORM_SERIAL_NUMBER is empty - OG file not generated\n');
      continue
   end
      
   fprintf('Creating: %s from %s\n', outFilePathName, inputFilePathName);

   % generate_OG NetCDF file
   gl_create_og_file(outFilePathName, ...
      ogGlobalAtt, ogTrajName, ogPlatformInfo, ogDeployInfo, ...
      ogFieldCompRef, ogHardwareInfo, ogTelecomInfo, ...
      ogParamList, ogSensorList, ogParamData);

end

return

% ------------------------------------------------------------------------------
% Fill OG data from EGO data.
%
% SYNTAX :
% [o_ogGlobalAtt, o_ogTrajName, o_ogPlatformInfo, o_ogDeployInfo, ...
%   o_ogFieldCompRef, o_ogHardwareInfo, o_ogTelecomInfo, ...
%   o_ogParamList, o_ogSensorList, o_ogParamData] = ego_2_og_mapping(a_inputFilePathName)
%
% INPUT PARAMETERS :
%   a_inputFilePathName : EGO file path name
%
% OUTPUT PARAMETERS :
%   o_ogGlobalAtt    : OG global attributes
%   o_ogTrajName     : OG trajectory name
%   o_ogPlatformInfo : OG platform information
%   o_ogDeployInfo   : OG deployment information
%   o_ogFieldCompRef : OG field comparison reference
%   o_ogHardwareInfo : OG hardware information
%   o_ogTelecomInfo  : OG telecom information
%   o_ogParamList    : OG parameter list
%   o_ogSensorList   : OG sensor list
%   o_ogParamData    : OG parameter measurements
%
% EXAMPLES :
%
% SEE ALSO :
% AUTHOR : Jean-Philippe Rannou (Capgemini) (jean.philippe.rannou@partenaire-exterieur.ifremer.fr)
% ------------------------------------------------------------------------------
% RELEASES :
%   02/05/2025 - RNU - creation
% ------------------------------------------------------------------------------
function [o_ogGlobalAtt, o_ogTrajName, o_ogPlatformInfo, o_ogDeployInfo, ...
   o_ogFieldCompRef, o_ogHardwareInfo, o_ogTelecomInfo, ...
   o_ogParamList, o_ogSensorList, o_ogParamData] = ego_2_og_mapping(a_inputFilePathName)

% output parameters initialization
o_ogGlobalAtt = [];
o_ogTrajName = [];
o_ogPlatformInfo = [];
o_ogDeployInfo  = [];
o_ogFieldCompRef = [];
o_ogHardwareInfo = [];
o_ogTelecomInfo = [];
o_ogParamList = [];
o_ogSensorList = [];
o_ogParamData = [];

% default values
global g_decGl_janFirst1950InMatlab;


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% MAPPING FILES

% read META_DATA mapping file
mapFileName = 'EGO_2_OG_META_DATA.txt';
if ~(exist(mapFileName, 'file') == 2)
   fprintf('ERROR: %s file should be in the Matlab path\n', mapFileName);
   return
end
fId = fopen(mapFileName, 'r');
if (fId == -1)
   fprintf('ERROR: Unable to open file: %s\n', mapFileName);
   return
end
mapData = textscan(fId, '%s', 'delimiter', '\t');
fclose(fId);
mapData = mapData{:};
ogMetaStructList = mapData(1:5:end);
ogMetaItemList = mapData(2:5:end);
egoMetaStructList = mapData(3:5:end);
egoMetaItemlist = mapData(4:5:end);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% read PARAMETER mapping file
mapFileName = 'EGO_2_OG_PARAMETER.txt';
if ~(exist(mapFileName, 'file') == 2)
   fprintf('ERROR: %s file should be in the Matlab path\n', mapFileName);
   return
end
fId = fopen(mapFileName, 'r');
if (fId == -1)
   fprintf('ERROR: Unable to open file: %s\n', mapFileName);
   return
end
mapData = textscan(fId, '%s', 'delimiter', '\t');
fclose(fId);
mapData = mapData{:};
paramMapData = [mapData(1:2:end), mapData(2:2:end)];

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% read PLATFORM_MAKER mapping file
mapFileName = 'EGO_2_OG_PLATFORM_MAKER.txt';
if ~(exist(mapFileName, 'file') == 2)
   fprintf('ERROR: %s file should be in the Matlab path\n', mapFileName);
   return
end
fId = fopen(mapFileName, 'r');
if (fId == -1)
   fprintf('ERROR: Unable to open file: %s\n', mapFileName);
   return
end
mapData = textscan(fId, '%s', 'delimiter', '\t');
fclose(fId);
mapData = mapData{:};
platformMakerMapData = [mapData(1:2:end), mapData(2:2:end)];

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% read PLATFORM_MODEL mapping file
mapFileName = 'EGO_2_OG_PLATFORM_MODEL.txt';
if ~(exist(mapFileName, 'file') == 2)
   fprintf('ERROR: %s file should be in the Matlab path\n', mapFileName);
   return
end
fId = fopen(mapFileName, 'r');
if (fId == -1)
   fprintf('ERROR: Unable to open file: %s\n', mapFileName);
   return
end
mapData = textscan(fId, '%s', 'delimiter', '\t');
fclose(fId);
mapData = mapData{:};
platformModelMapData = [mapData(1:2:end), mapData(2:2:end)];

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% read SENSOR_TYPE mapping file
mapFileName = 'EGO_2_OG_SENSOR_TYPE.txt';
if ~(exist(mapFileName, 'file') == 2)
   fprintf('ERROR: %s file should be in the Matlab path\n', mapFileName);
   return
end
fId = fopen(mapFileName, 'r');
if (fId == -1)
   fprintf('ERROR: Unable to open file: %s\n', mapFileName);
   return
end
mapData = textscan(fId, '%s', 'delimiter', '\t');
fclose(fId);
mapData = mapData{:};
sensorTypeMapData = [mapData(1:3:end), mapData(2:3:end), mapData(3:3:end)];

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% read SENSOR_MODEL mapping file
mapFileName = 'EGO_2_OG_SENSOR_MODEL.txt';
if ~(exist(mapFileName, 'file') == 2)
   fprintf('ERROR: %s file should be in the Matlab path\n', mapFileName);
   return
end
fId = fopen(mapFileName, 'r');
if (fId == -1)
   fprintf('ERROR: Unable to open file: %s\n', mapFileName);
   return
end
mapData = textscan(fId, '%s', 'delimiter', '\t');
fclose(fId);
mapData = mapData{:};
sensorModelMapData = [mapData(1:3:end), mapData(2:3:end), mapData(3:3:end)];

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% read SENSOR_MAKER mapping file
mapFileName = 'EGO_2_OG_SENSOR_MAKER.txt';
if ~(exist(mapFileName, 'file') == 2)
   fprintf('ERROR: %s file should be in the Matlab path\n', mapFileName);
   return
end
fId = fopen(mapFileName, 'r');
if (fId == -1)
   fprintf('ERROR: Unable to open file: %s\n', mapFileName);
   return
end
mapData = textscan(fId, '%s', 'delimiter', '\t');
fclose(fId);
mapData = mapData{:};
sensorMakerMapData = [mapData(1:3:end), mapData(2:3:end), mapData(3:3:end)];

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% read the EGO file contents
[egoFileDim, egoFileGlobalAtt, egoFileGliderCharacteristicsData, ...
   egoFileGliderDeploymentData, egoFileGpsData, egoFileTimeData, ...
   egoFileParameterList, egoFileMeasurementData, egoFileCurrentData, ...
   egoFileSensorInformationData, egoFileParameterInformationData, ...
   egoFileHistoryData, egoFileDerivationdata] = gl_read_file_ego(a_inputFilePathName);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% initialize OG information structures
ogGlobalAtt = gl_get_og_global_att_init_struct;
ogTrajName = gl_get_og_traj_name_init_struct;
ogPlatformInfo = gl_get_og_platform_info_init_struct;
ogDeployInfo = gl_get_og_deploy_info_init_struct;
ogFieldCompRef = gl_get_og_field_comp_ref_init_struct;
ogHardwareInfo = gl_get_og_hardware_info_init_struct;
ogTelecomInfo = gl_get_og_telecom_info_init_struct;

ogMetaList = unique(ogMetaStructList);
for id = 1:length(ogMetaList)
   egoStructName = ogMetaList{id};
   if (~isempty(egoStructName))

      switch (egoStructName)
         case 'ogGlobalAttributes'
            ogStruct = ogGlobalAtt;
         case 'ogTrajectoryName'
            ogStruct = ogTrajName;
         case 'ogPlatformInformation'
            ogStruct = ogPlatformInfo;
         case 'ogDeploymentInformation'
            ogStruct = ogDeployInfo;
         case 'ogFieldComparisonReference'
            ogStruct = ogFieldCompRef;
         case 'ogHardwareInformation'
            ogStruct = ogHardwareInfo;
         case 'ogTelecomInformation'
            ogStruct = ogTelecomInfo;
         otherwise
            fprintf('ERROR: Not managed egoStructName: %s\n', egoStructName);
      end
      
      lineId = find(strcmp(ogMetaStructList, egoStructName));
      for idL = lineId'
         ogItem = ogMetaItemList{idL};
         egoStruct = egoMetaStructList{idL};
         egoItem = egoMetaItemlist{idL};
         if (~isempty(egoStruct))
            switch egoStruct
               case 'comment'
               case 'egoGliderCharacteristics'
                  infoValue = gl_get_data_from_name(egoItem, egoFileGliderCharacteristicsData);
                  if (~isempty(infoValue))
                     if (ischar(infoValue))
                        if (size(infoValue, 2) > 1)
                           infoValue2 = [];
                           for idS = 1:size(infoValue, 2)
                              infoValue2{end+1} = strtrim(infoValue(:, idS)');
                           end
                           ogStruct.(ogItem) = infoValue2;
                        else
                           ogStruct.(ogItem) = strtrim(infoValue');
                        end
                     end
                  end
               case 'egoGliderDeploymentInformation'
                  infoValue = gl_get_data_from_name(egoItem, egoFileGliderDeploymentData);
                  if (~isempty(infoValue))
                     if (ischar(infoValue))
                        ogStruct.(ogItem) = strtrim(infoValue');
                     else
                        ogStruct.(ogItem) = infoValue;
                     end
                  end
               case 'egoGlobalAttributes'
                  infoValue = gl_get_data_from_name(egoItem, egoFileGlobalAtt);
                  if (~isempty(infoValue))
                     ogStruct.(ogItem) = infoValue;
                  end
               case 'value'
                  ogStruct.(ogItem) = egoItem;
               otherwise
                  fprintf('ERROR: Not managed egoStructName: %s\n', egoStruct);
            end
         end
      end

      switch (egoStructName)
         case 'ogGlobalAttributes'
            ogGlobalAtt = ogStruct;
         case 'ogTrajectoryName'
            ogTrajName = ogStruct;
         case 'ogPlatformInformation'
            ogPlatformInfo = ogStruct;
         case 'ogDeploymentInformation'
            ogDeployInfo = ogStruct;
         case 'ogFieldComparisonReference'
            ogFieldCompRef = ogStruct;
         case 'ogHardwareInformation'
            ogHardwareInfo = ogStruct;
         case 'ogTelecomInformation'
            ogTelecomInfo = ogStruct;
         otherwise
            fprintf('ERROR: Not managed egoStructName: %s\n', egoStructName);
      end
   end
end

% convert EGO reférence items into OG ones
% convert output formats
if (~isempty(ogGlobalAtt.start_date))
   ogGlobalAtt.start_date = datestr(datevec(ogGlobalAtt.start_date, 'yyyymmddHHMMSS'), 'yyyymmddTHHMMSS');
end
if (~isempty(ogGlobalAtt.date_created))
   ogGlobalAtt.date_created = datestr(datevec(ogGlobalAtt.date_created, 'yyyy-mm-ddTHH:MM:SSZ'), 'yyyymmddTHHMMSS');
end

if (~isempty(ogPlatformInfo.PLATFORM_MODEL))
   idF = find(strcmp(ogPlatformInfo.PLATFORM_MODEL, platformModelMapData(:, 1)), 1);
   if (~strcmp(platformModelMapData{idF, 2}, 'TBD'))
      ogPlatformInfo.PLATFORM_MODEL = platformModelMapData{idF, 2};
   else
      fprintf('WARNING: No link from EGO to OceanGliders for PLATFORM_MODEL ''%s'' data - using ''%s''\n', ...
         ogPlatformInfo.PLATFORM_MODEL, ['EGO_' ogPlatformInfo.PLATFORM_MODEL]);
      ogPlatformInfo.PLATFORM_MODEL = ['EGO_' ogPlatformInfo.PLATFORM_MODEL];
   end
end
if (~isempty(ogPlatformInfo.PLATFORM_MAKER))
   idF = find(strcmp(ogPlatformInfo.PLATFORM_MAKER, platformMakerMapData(:, 1)), 1);
   if (~strcmp(platformMakerMapData{idF, 2}, 'TBD'))
      ogPlatformInfo.PLATFORM_MAKER = platformMakerMapData{idF, 2};
   else
      fprintf('WARNING: No link from EGO to OceanGliders for PLATFORM_MAKER ''%s'' data - using ''%s''\n', ...
         ogPlatformInfo.PLATFORM_MAKER, ['EGO_' ogPlatformInfo.PLATFORM_MAKER]);
      ogPlatformInfo.PLATFORM_MAKER = ['EGO_' ogPlatformInfo.PLATFORM_MAKER];
   end
end

if (~isempty(ogDeployInfo.DEPLOYMENT_TIME))
   ogDeployInfo.DEPLOYMENT_TIME = gl_julian_2_epoch(datenum(ogDeployInfo.DEPLOYMENT_TIME, 'yyyymmddHHMMSS') - g_decGl_janFirst1950InMatlab);
end

if (~isempty(ogTelecomInfo.TELECOM_TYPE))
   if (iscell(ogTelecomInfo.TELECOM_TYPE))
      value = sprintf('%s,', ogTelecomInfo.TELECOM_TYPE{:});
      ogTelecomInfo.TELECOM_TYPE = value(1:end-1);
   end
end
if (~isempty(ogTelecomInfo.TRACKING_SYSTEM))
   if (iscell(ogTelecomInfo.TRACKING_SYSTEM))
      value = sprintf('%s,', ogTelecomInfo.TRACKING_SYSTEM{:});
      ogTelecomInfo.TRACKING_SYSTEM = value(1:end-1);
   end
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% DATA MEASUREMENTS

% merge data measurements in the same array
timeDim = gl_get_data_from_name('TIME', egoFileDim);
timeGpsDim = gl_get_data_from_name('TIME_GPS', egoFileDim);
timeCurrDim = gl_get_data_from_name('TIME_CURRENT', egoFileDim);
timeSurfCurrDim = gl_get_data_from_name('TIME_SURF_CURRENT', egoFileDim);

time = [];
timeGps = [];
timeCurr = [];
timeSurfCurr = [];
if (~isempty(timeDim))
   time = gl_get_data_from_name('TIME', egoFileTimeData);
end
if (~isempty(timeGpsDim))
   timeGps = gl_get_data_from_name('TIME_GPS', egoFileGpsData);
end
if (~isempty(timeCurrDim))
   timeCurr = gl_get_data_from_name('WATERCURRENTS_TIME', egoFileCurrentData);
end
if (~isempty(timeSurfCurrDim))
   timeSurfCurr = gl_get_data_from_name('SURF_WATERCURRENTS_TIME', egoFileCurrentData);
end
timeAll = unique([time; timeGps; timeCurr; timeSurfCurr]);
egoParamInfo = gl_get_ego_var_attributes('TIME');
timeAll(timeAll == egoParamInfo.FillValue) = [];

timeId = nan(size(time));
for id = 1:length(time)
   timeId(id) = find(timeAll == time(id), 1);
end
timeGpsId = nan(size(timeGps));
for id = 1:length(timeGps)
   timeGpsId(id) = find(timeAll == timeGps(id), 1);
end
timeCurrId = nan(size(timeCurr));
for id = 1:length(timeCurr)
   timeCurrId(id) = find(timeAll == timeCurr(id), 1);
end
timeSurfCurrId = nan(size(timeSurfCurr));
for id = 1:length(timeSurfCurr)
   timeSurfCurrId(id) = find(timeAll == timeSurfCurr(id), 1);
end

maxCol = (length(egoFileGpsData) + length(egoFileTimeData) + length(egoFileMeasurementData) + length(egoFileCurrentData))/2;
ogParamData = nan(length(timeAll), maxCol);
ogParamList = [];
egoParamList = [];
colNum = 1;

% coordinate variables
ogParamData(:, colNum) = timeAll;
ogParamList{end+1} = 'TIME';
egoParamList{end+1} = 'TIME';
colNum = colNum + 1;

longitude = gl_get_data_from_name('LONGITUDE', egoFileTimeData);
if (~isempty(longitude))
   egoParamInfo = gl_get_ego_var_attributes('LONGITUDE');
   longitude(longitude == egoParamInfo.FillValue) = nan;
   ogParamData(timeId, colNum) = longitude;
   ogParamList{end+1} = 'LONGITUDE';
   egoParamList{end+1} = 'LONGITUDE';
   colNum = colNum + 1;
end

latitude = gl_get_data_from_name('LATITUDE', egoFileTimeData);
if (~isempty(latitude))
   egoParamInfo = gl_get_ego_var_attributes('LATITUDE');
   latitude(latitude == egoParamInfo.FillValue) = nan;
   ogParamData(timeId, colNum) = latitude;
   ogParamList{end+1} = 'LATITUDE';
   egoParamList{end+1} = 'LATITUDE';
   colNum = colNum + 1;
end

pres = gl_get_data_from_name('PRES', egoFileMeasurementData);
if (~isempty(pres))
   pres = double(pres);
   egoParamInfo = gl_get_ego_var_attributes('PRES');
   pres(pres == egoParamInfo.FillValue) = nan;
   ogParamData(timeId, colNum) = pres;
   ogParamList{end+1} = 'DEPTH';
   egoParamList{end+1} = 'PRES';
   colNum = colNum + 1;
end
presQc = gl_get_data_from_name('PRES_QC', egoFileMeasurementData);
if (~isempty(presQc))
   presQc = double(presQc);
   presQc(presQc == -128) = nan;
   ogParamData(timeId, colNum) = presQc;
   ogParamList{end+1} = 'DEPTH_QC';
   egoParamList{end+1} = 'PRES_QC';
   colNum = colNum + 1;
end

% GPS variables
timeGps = gl_get_data_from_name('TIME_GPS', egoFileGpsData);
if (~isempty(timeGps))
   egoParamInfo = gl_get_ego_var_attributes('TIME_GPS');
   timeGps(timeGps == egoParamInfo.FillValue) = nan;
   ogParamData(timeGpsId, colNum) = timeGps;
   ogParamList{end+1} = 'TIME_GPS';
   egoParamList{end+1} = 'TIME_GPS';
   colNum = colNum + 1;
end

longitudeGps = gl_get_data_from_name('LONGITUDE_GPS', egoFileGpsData);
if (~isempty(longitudeGps))
   egoParamInfo = gl_get_ego_var_attributes('LONGITUDE_GPS');
   longitudeGps(longitudeGps == egoParamInfo.FillValue) = nan;
   ogParamData(timeGpsId, colNum) = longitudeGps;
   ogParamList{end+1} = 'LONGITUDE_GPS';
   egoParamList{end+1} = 'LONGITUDE_GPS';
   colNum = colNum + 1;
end

latitudeGps = gl_get_data_from_name('LATITUDE_GPS', egoFileGpsData);
if (~isempty(latitudeGps))
   egoParamInfo = gl_get_ego_var_attributes('LATITUDE_GPS');
   latitudeGps(latitudeGps == egoParamInfo.FillValue) = nan;
   ogParamData(timeGpsId, colNum) = latitudeGps;
   ogParamList{end+1} = 'LATITUDE_GPS';
   egoParamList{end+1} = 'LATITUDE_GPS';
   colNum = colNum + 1;
end

% PHASE variables
phase = gl_get_data_from_name('PHASE', egoFileTimeData);
if (~isempty(phase))
   phase = double(phase);
   phase(phase == -128) = nan;
   ogParamData(timeId, colNum) = phase;
   ogParamList{end+1} = 'PHASE';
   egoParamList{end+1} = 'PHASE';
   colNum = colNum + 1;
end

% WATERCURRENTS variables
wcParamList = [ ...
   [{'WATERCURRENTS_DEPTH'} {99999}]; ...
   [{'WATERCURRENTS_U'} {99999}]; ...
   [{'WATERCURRENTS_V'} {99999}]; ...
   [{'WATERCURRENTS_QC'} {-128}]; ...
   [{'WATERCURRENTS_ERROR'} {99999}]; ...
   [{'SURF_WATERCURRENTS_U'} {99999}]; ...
   [{'SURF_WATERCURRENTS_V'} {99999}]; ...
   [{'SURF_WATERCURRENTS_QC'} {-128}]; ...
   [{'SURF_WATERCURRENTS_ERROR'} {99999}] ...
   ];
for idP = 1:size(wcParamList, 1)
   egoParamName = wcParamList{idP, 1};
   egoParamFillValue = wcParamList{idP, 2};
   egoParamData = gl_get_data_from_name(egoParamName, egoFileCurrentData);
   if (~isempty(egoParamData))
      ogParamName = '';
      idF = find(strcmp(egoParamName, paramMapData(:, 1)), 1);
      if (~isempty(idF))
         if (~strcmp(paramMapData{idF, 2}, 'TBD'))
            ogParamName = paramMapData{idF, 2};
         end
      end
      if (isempty(ogParamName))
         fprintf('WARNING: OceanGliders parameter not found to store EGO parameter ''%s'' data  - data ignored\n', ...
            egoParamName);
         continue
      end
      egoParamData = double(egoParamData);
      egoParamData(egoParamData == egoParamFillValue) = nan;
      if (strncmp(egoParamName, 'WATERCURRENTS_', length('WATERCURRENTS_')))
         ogParamData(timeCurrId, colNum) = egoParamData;
      else
         ogParamData(timeSurfCurrId, colNum) = egoParamData;
      end
      ogParamList{end+1} = ogParamName;
      egoParamList{end+1} = egoParamName;
      colNum = colNum + 1;
   end
end

% geophysical variables
for idP = 1:length(egoFileParameterList)
   egoParamName = egoFileParameterList{idP};
   ogParamName = '';
   idF = find(strcmp(egoParamName, paramMapData(:, 1)), 1);
   if (~isempty(idF))
      if (~strcmp(paramMapData{idF, 2}, 'TBD'))
         ogParamName = paramMapData{idF, 2};
      end
   end
   if (isempty(ogParamName))
      fprintf('WARNING: OceanGliders parameter not found to store EGO parameter ''%s'' data  - data ignored\n', ...
         egoParamName);
      continue
   elseif (ismember(ogParamName, ogParamList))
      continue
   end
   egoParamData = gl_get_data_from_name(egoParamName, egoFileMeasurementData);
   if (~isempty(egoParamData))
      egoParamData = double(egoParamData);
      egoParamInfo = gl_get_ego_var_attributes(egoParamName);
      egoParamData(egoParamData == egoParamInfo.FillValue) = nan;
      ogParamData(timeId, colNum) = egoParamData;
      ogParamList{end+1} = ogParamName;
      egoParamList{end+1} = egoParamName;
      colNum = colNum + 1;
   end
   egoParamDataQc = gl_get_data_from_name([egoParamName '_QC'], egoFileMeasurementData);
   if (~isempty(egoParamDataQc))
      egoParamDataQc = double(egoParamDataQc);
      egoParamDataQc(egoParamDataQc == -128) = nan;
      ogParamData(timeId, colNum) = egoParamDataQc;
      ogParamList{end+1} = [ogParamName '_QC'];
      egoParamList{end+1} = [egoParamName '_QC'];
      colNum = colNum + 1;
   end
end
% remove unused columns
ogParamData(:, colNum:end) = [];
% remove unused levels
ogParamData(all(isnan(ogParamData(:, 2:end)), 2), :) = [];

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% PARAMETER AND SENSOR

% retrieve PARAMATER and SENSOR information from EGO file
egoParamIn = gl_get_data_from_name('PARAMETER', egoFileParameterInformationData);
egoParamSensorIn = gl_get_data_from_name('PARAMETER_SENSOR', egoFileParameterInformationData);

egoInputParamList = repmat({''}, size(egoParamIn, 2), 1);
for idP = 1:size(egoParamIn, 2)
   egoInputParamList{idP} = strtrim(egoParamIn(:, idP)');
end
egoInputParamSensorList = repmat({''}, size(egoParamSensorIn, 2), 1);
for idP = 1:size(egoParamSensorIn, 2)
   egoInputParamSensorList{idP} = strtrim(egoParamSensorIn(:, idP)');
end

egoSensorIn = gl_get_data_from_name('SENSOR', egoFileSensorInformationData);
egoSensorMakerIn = gl_get_data_from_name('SENSOR_MAKER', egoFileSensorInformationData);
egoSensorModelIn = gl_get_data_from_name('SENSOR_MODEL', egoFileSensorInformationData);
egoSensorSerialNoIn = gl_get_data_from_name('SENSOR_SERIAL_NO', egoFileSensorInformationData);

egoInputSensorList = repmat({''}, size(egoSensorIn, 2), 1);
for idS = 1:size(egoSensorIn, 2)
   egoInputSensorList{idS} = strtrim(egoSensorIn(:, idS)');
end
egoInputSensorMakerList = repmat({''}, size(egoSensorMakerIn, 2), 1);
for idS = 1:size(egoSensorMakerIn, 2)
   egoInputSensorMakerList{idS} = strtrim(egoSensorMakerIn(:, idS)');
end
egoInputSensorModelList = repmat({''}, size(egoSensorModelIn, 2), 1);
for idS = 1:size(egoSensorModelIn, 2)
   egoInputSensorModelList{idS} = strtrim(egoSensorModelIn(:, idS)');
end
egoInputSensorSerialNoList = repmat({''}, size(egoSensorSerialNoIn, 2), 1);
for idS = 1:size(egoSensorSerialNoIn, 2)
   egoInputSensorSerialNoList{idS} = strtrim(egoSensorSerialNoIn(:, idS)');
end

egoDerivParamIn = gl_get_data_from_name('DERIVATION_PARAMETER', egoFileDerivationdata);
egoDerivDateIn = gl_get_data_from_name('DERIVATION_DATE', egoFileDerivationdata);

egoDerivParamList = repmat({''}, size(egoDerivParamIn, 2), 1);
for idP = 1:size(egoDerivParamIn, 2)
   egoDerivParamList{idP} = strtrim(egoDerivParamIn(:, idP)');
end
egoDerivDateList = repmat({''}, size(egoDerivDateIn, 2), 1);
for idP = 1:size(egoDerivDateIn, 2)
   egoDerivDateList{idP} = strtrim(egoDerivDateIn(:, idP)');
end

egoInputSensorCalibDateList = repmat({''}, size(egoSensorIn, 2), 1);
for idP = 1:length(egoDerivParamList)
   derivDate = egoDerivDateList{idP};
   if (~isempty(derivDate))
      derivParam = egoDerivParamList{idP};
      idParam = find(strcmp(derivParam, egoInputParamList), 1);
      if (~isempty(idParam))
         sensorName = egoInputParamSensorList{idParam};
         idSensor = find(strcmp(sensorName, egoInputSensorList), 1);
         if (~isempty(idSensor))
            if (~isempty(egoInputSensorCalibDateList{idSensor}))
               currentDate = datenum(egoInputSensorCalibDateList{idSensor}, 'yyyy-mm-dd');
               newDate = datenum(derivDate, 'yyyymmddHHMMSS');
               if (newDate < currentDate) % choose the earliest time, supposed to be the sensor calibration time
                  egoInputSensorCalibDateList{idSensor} = datestr(datenum(derivDate, 'yyyymmddHHMMSS'), 'yyyy-mm-dd');
               end
            else
               egoInputSensorCalibDateList{idSensor} = datestr(datenum(derivDate, 'yyyymmddHHMMSS'), 'yyyy-mm-dd');
            end
         end
      end
   end
end

% use ogParamList to manage PARAMETERS and SENSORS
ogParamSensorList = repmat({''}, size(ogParamList));
ogSensorTypeList = repmat({''}, size(ogParamList));
ogSensorTypeVocabList = repmat({''}, size(ogParamList));
ogSensorMakerList = repmat({''}, size(ogParamList));
ogSensorMakerVocabList = repmat({''}, size(ogParamList));
ogSensorModelList = repmat({''}, size(ogParamList));
ogSensorModelVocabList = repmat({''}, size(ogParamList));
ogSensorSerialNoList = repmat({''}, size(ogParamList));
ogSensorCalibDateList = repmat({''}, size(ogParamList));

for idP = 1:length(ogParamList)
   ogParamName  = ogParamList{idP};
   if ((length(ogParamName) > 2) && strcmp(ogParamName(end-2:end), '_QC'))
      continue
   end
   egoParamName  = egoParamList{idP};

   idParam = find(strcmp(egoInputParamList, egoParamName));
   if (~isempty(idParam)) % coordinate variables are not in egoFileParameterInformationData

      egoParamSensor = egoInputParamSensorList{idParam};
      ogParamSensor = '';
      ogParamSensorVocab = '';
      idSensor = find(strcmp(egoParamSensor, sensorTypeMapData(:, 1)), 1);
      if (~isempty(idSensor)) % GLIDER_TECH not in ref. list
         if (~strcmp(sensorTypeMapData{idSensor, 2}, 'TBD'))
            ogParamSensor  = sensorTypeMapData{idSensor, 2};
            ogParamSensorVocab  = sensorTypeMapData{idSensor, 3};
         end
      end
      if (isempty(ogParamSensor))
         fprintf('WARNING: No link from EGO to OceanGliders for SENSOR_TYPE ''%s'' data - using ''%s''\n', ...
            egoParamSensor, ['EGO_' egoParamSensor]);
         ogParamSensor  = ['EGO_' egoParamSensor];
      end
      ogParamSensorList{idP}  = ogParamSensor;
      ogSensorTypeList{idP}  = ogParamSensor;
      ogSensorTypeVocabList{idP}  = ogParamSensorVocab;

      idSensor = find(strcmp(egoParamSensor, egoInputSensorList), 1);
      egoSensorMaker = egoInputSensorMakerList{idSensor};
      egoSensorModel = egoInputSensorModelList{idSensor};
      egoSensorSerialNo = egoInputSensorSerialNoList{idSensor};
      egoSensorCalibDate = egoInputSensorCalibDateList{idSensor};

      ogSensorSerialNoList{idP} = egoSensorSerialNo;
      ogSensorCalibDateList{idP} = egoSensorCalibDate;

      ogSensorMaker = '';
      ogSensorMakerVocab = '';
      idSensor = find(strcmp(egoSensorMaker, sensorMakerMapData(:, 1)), 1);
      if (~isempty(idSensor))
         if (~strcmp(sensorMakerMapData{idSensor, 2}, 'TBD'))
            ogSensorMaker  = sensorMakerMapData{idSensor, 2};
            ogSensorMakerVocab  = sensorMakerMapData{idSensor, 3};
         end
      end
      if (isempty(ogSensorMaker) && ~isempty(egoSensorMaker))
         fprintf('WARNING: No link from EGO to OceanGliders for SENSOR_MAKER ''%s'' data - using ''%s''\n', ...
            egoSensorMaker, ['EGO_' egoSensorMaker]);
         ogSensorMaker  = ['EGO_' egoSensorMaker];
      end
      ogSensorMakerList{idP}  = ogSensorMaker;
      ogSensorMakerVocabList{idP}  = ogSensorMakerVocab;

      ogSensorModel = '';
      ogSensorModelVocab = '';
      idSensor = find(strcmp(egoSensorModel, sensorModelMapData(:, 1)), 1);
      if (~isempty(idSensor))
         if (~strcmp(sensorModelMapData{idSensor, 2}, 'TBD'))
            ogSensorModel  = sensorModelMapData{idSensor, 2};
            ogSensorModelVocab  = sensorModelMapData{idSensor, 3};
         end
      end
      if (isempty(ogSensorModel) && ~isempty(egoSensorModel))
         fprintf('WARNING: No link from EGO to OceanGliders for SENSOR_MODEL''%s'' data - using ''%s''\n', ...
            egoSensorModel, ['EGO_' egoSensorModel]);
         ogSensorModel  = ['EGO_' egoSensorModel];
      end
      ogSensorModelList{idP}  = ogSensorModel;
      ogSensorModelVocabList{idP}  = ogSensorModelVocab;
   end
end

% compute additional metedata
varLatList = [{'LATITUDE'} {'LATITUDE_GPS'}];
latData = [];
for idV = 1:length(varLatList)
   idLat = find(strcmp(varLatList{idV}, ogParamList));
   if (~isempty(idLat))
      latData = [latData; ogParamData(:, idLat)];
   end
end
latData(isnan(latData)) = [];
ogGlobalAtt.geospatial_lat_min = min(latData);
ogGlobalAtt.geospatial_lat_max = max(latData);

varLonList = [{'LONGITUDE'} {'LONGITUDE_GPS'}];
lonData = [];
for idV = 1:length(varLonList)
   idLon = find(strcmp(varLonList{idV}, ogParamList));
   if (~isempty(idLon))
      lonData = [lonData; ogParamData(:, idLon)];
   end
end
lonData(isnan(lonData)) = [];
ogGlobalAtt.geospatial_lon_min = min(lonData);
ogGlobalAtt.geospatial_lon_max = max(lonData);

idDepth = find(strcmp('DEPTH', ogParamList));
depthData = ogParamData(:, idDepth);
depthData(isnan(depthData)) = [];
ogGlobalAtt.geospatial_vertical_min = min(depthData);
ogGlobalAtt.geospatial_vertical_max = max(depthData);

idTime = find(strcmp('TIME', ogParamList));
timeData = ogParamData(:, idTime);
timeData(isnan(timeData)) = [];
ogGlobalAtt.time_coverage_start = datestr(gl_epoch_2_julian(min(timeData)) + g_decGl_janFirst1950InMatlab, 'yyyymmddTHHMMSS');
ogGlobalAtt.time_coverage_end = datestr(gl_epoch_2_julian(max(timeData)) + g_decGl_janFirst1950InMatlab, 'yyyymmddTHHMMSS');

% output parameters
o_ogGlobalAtt = ogGlobalAtt;
o_ogTrajName = ogTrajName;
o_ogPlatformInfo = ogPlatformInfo;
o_ogDeployInfo = ogDeployInfo;
o_ogFieldCompRef = ogFieldCompRef;
o_ogHardwareInfo = ogHardwareInfo;
o_ogTelecomInfo = ogTelecomInfo;
o_ogParamList = ogParamList;
o_ogSensorList.sensorType = ogSensorTypeList;
o_ogSensorList.sensorTypeVocab = ogSensorTypeVocabList;
o_ogSensorList.sensorMaker = ogSensorMakerList;
o_ogSensorList.sensorMakerVocab = ogSensorMakerVocabList;
o_ogSensorList.sensorModel = ogSensorModelList;
o_ogSensorList.sensorModelVocab = ogSensorModelVocabList;
o_ogSensorList.sensorSerialNo = ogSensorSerialNoList;
o_ogSensorList.sensorCalibDate = ogSensorCalibDateList;
o_ogParamData = ogParamData;

return

% ------------------------------------------------------------------------------
% Create OceanGliders NetCDF file.
%
% SYNTAX :
% gl_create_og_file(a_outFilePathName, ...
%   a_ogGlobalAtt, a_ogTrajName, a_ogPlatformInfo, a_ogDeployInfo, ...
%   a_ogFieldCompRef, a_ogHardwareInfo, a_ogTelecomInfo, ...
%   a_ogParamList, a_ogSensorList, a_ogParamData)
%
% INPUT PARAMETERS :
%   a_inputPathFileName : OG file path name
%   a_ogGlobalAtt       : OG global attributes
%   a_ogTrajName        : OG trajectory name
%   a_ogPlatformInfo    : OG platform information
%   a_ogDeployInfo      : OG deployment information
%   a_ogFieldCompRef    : OG field comparison reference
%   a_ogHardwareInfo    : OG hardware information
%   a_ogTelecomInfo     : OG telecom information
%   a_ogParamList       : OG parameter list
%   a_ogSensorList      : OG sensor list
%   a_ogParamData       : OG parameter measurements
%
% OUTPUT PARAMETERS :
%
% EXAMPLES :
%
% SEE ALSO :
% AUTHOR : Jean-Philippe Rannou (Capgemini) (jean.philippe.rannou@partenaire-exterieur.ifremer.fr)
% ------------------------------------------------------------------------------
% RELEASES :
%   02/04/2025 - RNU - creation
% ------------------------------------------------------------------------------
function gl_create_og_file(a_outFilePathName, ...
   a_ogGlobalAtt, a_ogTrajName, a_ogPlatformInfo, a_ogDeployInfo, ...
   a_ogFieldCompRef, a_ogHardwareInfo, a_ogTelecomInfo, ...
   a_ogParamList, a_ogSensorList, a_ogParamData)

% real time processing
global g_decGl_realtimeFlag;

% report information structure
global g_decGl_reportStruct;


% try

   % create and open output NetCDF file
   mode = netcdf.getConstant('NC_CLOBBER');
   mode = bitor(mode, netcdf.getConstant('NETCDF4'));
   fCdf = netcdf.create(a_outFilePathName, mode);
   if (isempty(fCdf))
      fprintf('ERROR: Unable to create NetCDF output file: %s\n', a_outFilePathName);
      return
   end

   %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
   % DEFINE MODE BEGIN

   ncParamNameList = [];

   % create dimensions
   nMeasurementsDimId = netcdf.defDim(fCdf, 'N_MEASUREMENTS', netcdf.getConstant('NC_UNLIMITED'));

   % global attributes
   globalVarId = netcdf.getConstant('NC_GLOBAL');
   netcdf.putAtt(fCdf, globalVarId, 'title', a_ogGlobalAtt.title);
   netcdf.putAtt(fCdf, globalVarId, 'platform', a_ogGlobalAtt.platform);
   netcdf.putAtt(fCdf, globalVarId, 'platform_vocabulary', a_ogGlobalAtt.platform_vocabulary);
   netcdf.putAtt(fCdf, globalVarId, 'id', a_ogGlobalAtt.id);
   netcdf.putAtt(fCdf, globalVarId, 'naming_authority', a_ogGlobalAtt.naming_authority);
   netcdf.putAtt(fCdf, globalVarId, 'institution', a_ogGlobalAtt.institution);
   netcdf.putAtt(fCdf, globalVarId, 'internal_mission_identifier', a_ogGlobalAtt.internal_mission_identifier);
   netcdf.putAtt(fCdf, globalVarId, 'geospatial_lat_min', a_ogGlobalAtt.geospatial_lat_min);
   netcdf.putAtt(fCdf, globalVarId, 'geospatial_lat_max', a_ogGlobalAtt.geospatial_lat_max);
   netcdf.putAtt(fCdf, globalVarId, 'geospatial_lon_min', a_ogGlobalAtt.geospatial_lon_min);
   netcdf.putAtt(fCdf, globalVarId, 'geospatial_lon_max', a_ogGlobalAtt.geospatial_lon_max);
   netcdf.putAtt(fCdf, globalVarId, 'geospatial_vertical_min', a_ogGlobalAtt.geospatial_vertical_min);
   netcdf.putAtt(fCdf, globalVarId, 'geospatial_vertical_max', a_ogGlobalAtt.geospatial_vertical_max);
   netcdf.putAtt(fCdf, globalVarId, 'time_coverage_start', a_ogGlobalAtt.time_coverage_start);
   netcdf.putAtt(fCdf, globalVarId, 'time_coverage_end', a_ogGlobalAtt.time_coverage_end);
   netcdf.putAtt(fCdf, globalVarId, 'site', a_ogGlobalAtt.site);
   netcdf.putAtt(fCdf, globalVarId, 'site_vocabulary', a_ogGlobalAtt.site_vocabulary);
   netcdf.putAtt(fCdf, globalVarId, 'program', a_ogGlobalAtt.program);
   netcdf.putAtt(fCdf, globalVarId, 'program_vocabulary', a_ogGlobalAtt.program_vocabulary);
   netcdf.putAtt(fCdf, globalVarId, 'project', a_ogGlobalAtt.project);
   netcdf.putAtt(fCdf, globalVarId, 'network', a_ogGlobalAtt.network);
   netcdf.putAtt(fCdf, globalVarId, 'contributor_name', a_ogGlobalAtt.contributor_name);
   netcdf.putAtt(fCdf, globalVarId, 'contributor_email', a_ogGlobalAtt.contributor_email);
   netcdf.putAtt(fCdf, globalVarId, 'contributor_id', a_ogGlobalAtt.contributor_id);
   netcdf.putAtt(fCdf, globalVarId, 'contributor_role', a_ogGlobalAtt.contributor_role);
   netcdf.putAtt(fCdf, globalVarId, 'contributor_role_vocabulary', a_ogGlobalAtt.contributor_role_vocabulary);
   netcdf.putAtt(fCdf, globalVarId, 'contributing_institutions', a_ogGlobalAtt.contributing_institutions);
   netcdf.putAtt(fCdf, globalVarId, 'contributing_institutions_vocabulary', a_ogGlobalAtt.contributing_institutions_vocabulary);
   netcdf.putAtt(fCdf, globalVarId, 'contributing_institutions_role', a_ogGlobalAtt.contributing_institutions_role);
   netcdf.putAtt(fCdf, globalVarId, 'contributing_institutions_role_vocabulary', a_ogGlobalAtt.contributing_institutions_role_vocabulary);
   netcdf.putAtt(fCdf, globalVarId, 'uri', a_ogGlobalAtt.uri);
   netcdf.putAtt(fCdf, globalVarId, 'data_url', a_ogGlobalAtt.data_url);
   netcdf.putAtt(fCdf, globalVarId, 'doi', a_ogGlobalAtt.doi);
   netcdf.putAtt(fCdf, globalVarId, 'rtqc_method', a_ogGlobalAtt.rtqc_method);
   netcdf.putAtt(fCdf, globalVarId, 'rtqc_method_doi', a_ogGlobalAtt.rtqc_method_doi);
   netcdf.putAtt(fCdf, globalVarId, 'web_link', a_ogGlobalAtt.web_link);
   netcdf.putAtt(fCdf, globalVarId, 'comment', a_ogGlobalAtt.comment);
   netcdf.putAtt(fCdf, globalVarId, 'start_date', a_ogGlobalAtt.start_date);
   netcdf.putAtt(fCdf, globalVarId, 'date_created', a_ogGlobalAtt.date_created);
   netcdf.putAtt(fCdf, globalVarId, 'featureType', a_ogGlobalAtt.featureType);
   netcdf.putAtt(fCdf, globalVarId, 'Conventions', a_ogGlobalAtt.Conventions);

   % coordinate variables
   timeVarId = netcdf.defVar(fCdf, 'TIME', 'NC_DOUBLE', nMeasurementsDimId);
   netcdf.putAtt(fCdf, timeVarId, 'long_name', 'Time elapsed since 1970-01-01T00:00:00Z');
   netcdf.putAtt(fCdf, timeVarId, 'calendar', 'gregorian');
   netcdf.putAtt(fCdf, timeVarId, 'units', 'seconds since 1970-01-01T00:00:00Z');
   netcdf.putAtt(fCdf, timeVarId, '_FillValue', double(-1.0));
   netcdf.putAtt(fCdf, timeVarId, 'valid_min', double(1e9));
   netcdf.putAtt(fCdf, timeVarId, 'valid_max', double(4e9));
   netcdf.putAtt(fCdf, timeVarId, 'ancillary_variables', 'TIME_QC');
   netcdf.putAtt(fCdf, timeVarId, 'interpolation_methodology', '');
   netcdf.putAtt(fCdf, timeVarId, 'time_vocabulary', 'https://vocab.nerc.ac.uk/collection/OG1/current/TIME/');
   ncParamNameList{end+1} = 'TIME';

   longitudeVarId = netcdf.defVar(fCdf, 'LONGITUDE', 'NC_DOUBLE', nMeasurementsDimId);
   netcdf.putAtt(fCdf, longitudeVarId, 'long_name', 'longitude of each measurement and GPS location');
   netcdf.putAtt(fCdf, longitudeVarId, 'standard_name', 'longitude');
   netcdf.putAtt(fCdf, longitudeVarId, 'units', 'degrees_east');
   netcdf.putAtt(fCdf, longitudeVarId, '_FillValue', double(-9999.9));
   netcdf.putAtt(fCdf, longitudeVarId, 'valid_min', double(-180.0));
   netcdf.putAtt(fCdf, longitudeVarId, 'valid_max', double(180.0));
   netcdf.putAtt(fCdf, longitudeVarId, 'ancillary_variables', 'LONGITUDE_QC');
   netcdf.putAtt(fCdf, longitudeVarId, 'interpolation_methodology', '');
   netcdf.putAtt(fCdf, longitudeVarId, 'longitude_vocabulary', 'https://vocab.nerc.ac.uk/collection/OG1/current/LON/');
   ncParamNameList{end+1} = 'LONGITUDE';

   latitudeVarId = netcdf.defVar(fCdf, 'LATITUDE', 'NC_DOUBLE', nMeasurementsDimId);
   netcdf.putAtt(fCdf, latitudeVarId, 'long_name', 'Latitude north (WGS84)');
   netcdf.putAtt(fCdf, latitudeVarId, 'standard_name', 'latitude');
   netcdf.putAtt(fCdf, latitudeVarId, 'units', 'degrees_north');
   netcdf.putAtt(fCdf, latitudeVarId, '_FillValue', double(-9999.9));
   netcdf.putAtt(fCdf, latitudeVarId, 'valid_min', double(-90.0));
   netcdf.putAtt(fCdf, latitudeVarId, 'valid_max', double(90.0));
   netcdf.putAtt(fCdf, latitudeVarId, 'ancillary_variables', 'LATITUDE_QC');
   netcdf.putAtt(fCdf, latitudeVarId, 'interpolation_methodology', '');
   netcdf.putAtt(fCdf, latitudeVarId, 'longitude_vocabulary', 'https://vocab.nerc.ac.uk/collection/OG1/current/LAT/');
   ncParamNameList{end+1} = 'LATITUDE';

   depthVarId = netcdf.defVar(fCdf, 'DEPTH', 'NC_DOUBLE', nMeasurementsDimId);
   netcdf.putAtt(fCdf, depthVarId, 'long_name', 'Depth below surface of the water body by unknown instrument and correction to zero at sea level using unspecified algorithm.');
   netcdf.putAtt(fCdf, depthVarId, 'standard_name', 'depth');
   netcdf.putAtt(fCdf, depthVarId, 'units', 'metres');
   netcdf.putAtt(fCdf, depthVarId, '_FillValue', double(-9999.9));
   netcdf.putAtt(fCdf, depthVarId, 'valid_min', double(0.0));
   netcdf.putAtt(fCdf, depthVarId, 'valid_max', double(10000.0));
   netcdf.putAtt(fCdf, depthVarId, 'ancillary_variables', 'DEPTH_QC');
   netcdf.putAtt(fCdf, depthVarId, 'interpolation_methodology', '');
   netcdf.putAtt(fCdf, depthVarId, 'longitude_vocabulary', 'https://vocab.nerc.ac.uk/collection/OG1/current/DEPTH/');
   ncParamNameList{end+1} = 'DEPTH';

   % GPS variables
   timeGpsVarId = netcdf.defVar(fCdf, 'TIME_GPS', 'NC_DOUBLE', nMeasurementsDimId);
   netcdf.putAtt(fCdf, timeGpsVarId, 'long_name', 'time of each GPS location');
   netcdf.putAtt(fCdf, timeGpsVarId, 'calendar', 'gregorian');
   netcdf.putAtt(fCdf, timeGpsVarId, 'units', 'seconds since 1970-01-01T00:00:00Z');
   netcdf.putAtt(fCdf, timeGpsVarId, '_FillValue', double(-1.0));
   netcdf.putAtt(fCdf, timeGpsVarId, 'valid_min', double(1e9));
   netcdf.putAtt(fCdf, timeGpsVarId, 'valid_max', double(4e9));
   netcdf.putAtt(fCdf, timeGpsVarId, 'ancillary_variables', 'TIME_GPS_QC');
   ncParamNameList{end+1} = 'TIME_GPS';

   longitudeGpsVarId = netcdf.defVar(fCdf, 'LONGITUDE_GPS', 'NC_DOUBLE', nMeasurementsDimId);
   netcdf.putAtt(fCdf, longitudeGpsVarId, 'long_name', 'longitude of each GPS location');
   netcdf.putAtt(fCdf, longitudeGpsVarId, 'standard_name', 'longitude');
   netcdf.putAtt(fCdf, longitudeGpsVarId, 'units', 'degrees_east');
   netcdf.putAtt(fCdf, longitudeGpsVarId, '_FillValue', double(-9999.9));
   netcdf.putAtt(fCdf, longitudeGpsVarId, 'valid_min', double(-180.0));
   netcdf.putAtt(fCdf, longitudeGpsVarId, 'valid_max', double(180.0));
   netcdf.putAtt(fCdf, longitudeGpsVarId, 'ancillary_variables', 'LONGITUDE_GPS_QC');
   ncParamNameList{end+1} = 'LONGITUDE_GPS';

   latitudeGpsVarId = netcdf.defVar(fCdf, 'LATITUDE_GPS', 'NC_DOUBLE', nMeasurementsDimId);
   netcdf.putAtt(fCdf, latitudeGpsVarId, 'long_name', 'latitude of each GPS location');
   netcdf.putAtt(fCdf, latitudeGpsVarId, 'standard_name', 'latitude');
   netcdf.putAtt(fCdf, latitudeGpsVarId, 'units', 'degrees_north');
   netcdf.putAtt(fCdf, latitudeGpsVarId, '_FillValue', double(-9999.9));
   netcdf.putAtt(fCdf, latitudeGpsVarId, 'valid_min', double(-90.0));
   netcdf.putAtt(fCdf, latitudeGpsVarId, 'valid_max', double(90.0));
   netcdf.putAtt(fCdf, latitudeGpsVarId, 'ancillary_variables', 'LATITUDE_GPS_QC');
   ncParamNameList{end+1} = 'LATITUDE_GPS';

   % trajectory name variable
   trajectoryVarId = netcdf.defVar(fCdf, 'TRAJECTORY', 'NC_STRING', []);
   netcdf.putAtt(fCdf, trajectoryVarId, 'cf_role', 'trajectory_id');
   netcdf.putAtt(fCdf, trajectoryVarId, 'long_name', 'trajectory name');
   ncParamNameList{end+1} = 'TRAJECTORY';

   % platform information variables
   wmoIdentifierVarId = netcdf.defVar(fCdf, 'WMO_IDENTIFIER', 'NC_STRING', []);
   netcdf.putAtt(fCdf, wmoIdentifierVarId, 'long_name', 'wmo id');
   ncParamNameList{end+1} = 'WMO_IDENTIFIER';

   platformModelVarId = netcdf.defVar(fCdf, 'PLATFORM_MODEL', 'NC_STRING', []);
   netcdf.putAtt(fCdf, platformModelVarId, 'long_name', 'model of the glider');
   netcdf.putAtt(fCdf, platformModelVarId, 'platform_model_vocabulary', '');
   ncParamNameList{end+1} = 'PLATFORM_MODEL';

   platformSerialNumberVarId = netcdf.defVar(fCdf, 'PLATFORM_SERIAL_NUMBER', 'NC_STRING', []);
   netcdf.putAtt(fCdf, platformSerialNumberVarId, 'long_name', 'glider serial number');
   ncParamNameList{end+1} = 'PLATFORM_SERIAL_NUMBER';

   platformNameVarId = netcdf.defVar(fCdf, 'PLATFORM_NAME', 'NC_STRING', []);
   netcdf.putAtt(fCdf, platformNameVarId, 'long_name', 'Local or nickname of the glider');
   ncParamNameList{end+1} = 'PLATFORM_NAME';

   platformDepthRatingVarId = netcdf.defVar(fCdf, 'PLATFORM_DEPTH_RATING', 'NC_STRING', []);
   netcdf.putAtt(fCdf, platformDepthRatingVarId, 'long_name', 'depth limit in meters of the glider for this mission');
   netcdf.putAtt(fCdf, platformDepthRatingVarId, 'convention', 'positive value expected - e.g. 100m depth = 100');
   ncParamNameList{end+1} = 'PLATFORM_DEPTH_RATING';

   icesCodeVarId = netcdf.defVar(fCdf, 'ICES_CODE', 'NC_STRING', []);
   netcdf.putAtt(fCdf, icesCodeVarId, 'long_name', 'ICES platform code of the glider');
   netcdf.putAtt(fCdf, icesCodeVarId, 'ices_code_vocabulary', '');
   ncParamNameList{end+1} = 'ICES_CODE';

   platformMakerVarId = netcdf.defVar(fCdf, 'PLATFORM_MAKER', 'NC_STRING', []);
   netcdf.putAtt(fCdf, platformMakerVarId, 'long_name', 'glider manufacturer');
   netcdf.putAtt(fCdf, platformMakerVarId, 'platform_maker_vocabulary', '');
   ncParamNameList{end+1} = 'PLATFORM_MAKER';

   % deployment information variables
   deploymentTimeVarId = netcdf.defVar(fCdf, 'DEPLOYMENT_TIME', 'NC_DOUBLE', []);
   netcdf.putAtt(fCdf, deploymentTimeVarId, 'long_name', 'date of deployment');
   netcdf.putAtt(fCdf, deploymentTimeVarId, 'standard_name', 'time');
   netcdf.putAtt(fCdf, deploymentTimeVarId, 'calendar', 'gregorian');
   netcdf.putAtt(fCdf, deploymentTimeVarId, 'units', 'seconds since 1970-01-01T00:00:00Z');
   ncParamNameList{end+1} = 'DEPLOYMENT_TIME';

   deploymentLatitudeVarId = netcdf.defVar(fCdf, 'DEPLOYMENT_LATITUDE', 'NC_DOUBLE', []);
   netcdf.putAtt(fCdf, deploymentLatitudeVarId, 'long_name', 'latitude of deployment');
   ncParamNameList{end+1} = 'DEPLOYMENT_LATITUDE';

   deploymentLongitudeVarId = netcdf.defVar(fCdf, 'DEPLOYMENT_LONGITUDE', 'NC_DOUBLE', []);
   netcdf.putAtt(fCdf, deploymentLongitudeVarId, 'long_name', 'longitude of deployment');
   ncParamNameList{end+1} = 'DEPLOYMENT_LONGITUDE';

   % field comparison information variable
   fieldComparisonReferenceVarId = netcdf.defVar(fCdf, 'FIELD_COMPARISON_REFERENCE', 'NC_STRING', []);
   netcdf.putAtt(fCdf, fieldComparisonReferenceVarId, 'long_name', 'links (uri or url) to supplementary data that can provide field comparison for platform sensors.');
   netcdf.putAtt(fCdf, fieldComparisonReferenceVarId, 'comment', 'multiple links are separated by a comma');
   ncParamNameList{end+1} = 'FIELD_COMPARISON_REFERENCE';

   % hardware information variables
   gliderFirmwareVersionVarId = netcdf.defVar(fCdf, 'GLIDER_FIRMWARE_VERSION', 'NC_STRING', []);
   netcdf.putAtt(fCdf, gliderFirmwareVersionVarId, 'long_name', 'version of the internal glider firmware');
   ncParamNameList{end+1} = 'GLIDER_FIRMWARE_VERSION';

   landstationVersionVarId = netcdf.defVar(fCdf, 'LANDSTATION_VERSION', 'NC_STRING', []);
   netcdf.putAtt(fCdf, landstationVersionVarId, 'long_name', 'version of the server onshore');
   ncParamNameList{end+1} = 'LANDSTATION_VERSION';

   batteryTypeVarId = netcdf.defVar(fCdf, 'BATTERY_TYPE', 'NC_STRING', []);
   netcdf.putAtt(fCdf, batteryTypeVarId, 'long_name', 'type of the battery');
   netcdf.putAtt(fCdf, batteryTypeVarId, 'battery_type_vocabulary', 'https://github.com/OceanGlidersCommunity/OG-format-user-manual/blob/main/vocabularyCollection/battery_type.md');
   ncParamNameList{end+1} = 'BATTERY_TYPE';

   batteryPackVarId = netcdf.defVar(fCdf, 'BATTERY_PACK', 'NC_STRING', []);
   netcdf.putAtt(fCdf, batteryPackVarId, 'long_name', 'battery packaging');
   ncParamNameList{end+1} = 'BATTERY_PACK';

   % telecom information variables
   telecomTypeVarId = netcdf.defVar(fCdf, 'TELECOM_TYPE', 'NC_STRING', []);
   netcdf.putAtt(fCdf, telecomTypeVarId, 'long_name', 'types of telecommunication systems used by the glider, multiple telecom type are separated by a comma');
   netcdf.putAtt(fCdf, telecomTypeVarId, 'telecom_type_vocabulary', 'https://github.com/OceanGlidersCommunity/OG-format-user-manual/blob/main/vocabularyCollection/telecom_type.md');
   ncParamNameList{end+1} = 'TELECOM_TYPE';

   trackingSystemVarId = netcdf.defVar(fCdf, 'TRACKING_SYSTEM', 'NC_STRING', []);
   netcdf.putAtt(fCdf, trackingSystemVarId, 'long_name', 'type of tracking systems used by the glider, multiple tracking system are separated by a comma');
   netcdf.putAtt(fCdf, trackingSystemVarId, 'tracking_system_vocabulary', 'https://github.com/OceanGlidersCommunity/OG-format-user-manual/blob/main/vocabularyCollection/tracking_system.md');
   ncParamNameList{end+1} = 'TRACKING_SYSTEM';

   % PHASE variables
   phaseVarId = netcdf.defVar(fCdf, 'PHASE', 'NC_BYTE', nMeasurementsDimId);
   netcdf.putAtt(fCdf, phaseVarId, 'long_name', 'behavior of the glider at sea');
   netcdf.putAtt(fCdf, phaseVarId, 'phase_vocabulary', 'https://github.com/OceanGlidersCommunity/OG-format-user-manual/blob/main/vocabularyCollection/phase.md');
   netcdf.putAtt(fCdf, phaseVarId, '_FillValue', int8(0));
   netcdf.putAtt(fCdf, phaseVarId, 'phase_calculation_method', '');
   netcdf.putAtt(fCdf, phaseVarId, 'phase_calculation_method_vocabulary', '');
   netcdf.putAtt(fCdf, phaseVarId, 'ancillary_variables', 'PHASE_QC');
   ncParamNameList{end+1} = 'PHASE';

   phaseQcVarId = netcdf.defVar(fCdf, 'PHASE_QC', 'NC_BYTE', nMeasurementsDimId);
   netcdf.putAtt(fCdf, phaseQcVarId, 'long_name', 'quality flag');
   netcdf.putAtt(fCdf, phaseQcVarId, '_FillValue', int8(' '));
   netcdf.putAtt(fCdf, phaseQcVarId, 'valid_range', int8(0:4));
   netcdf.putAtt(fCdf, phaseQcVarId, 'flag_values', int8(0:4));
   netcdf.putAtt(fCdf, phaseQcVarId, 'flag_meanings', 'No QC has been applied, Good data, Probably good data, Probably bad data, Bad data');
   ncParamNameList{end+1} = 'PHASE_QC';

   % sensor information variables
   for idS = 1:length(a_ogSensorList.sensorType)
      sensorType = a_ogSensorList.sensorType{idS};
      if (isempty(sensorType))
         continue
      end
      sensorTypeVocab = a_ogSensorList.sensorTypeVocab{idS};
      sensorMaker = a_ogSensorList.sensorMaker{idS};
      sensorMakerVocab = a_ogSensorList.sensorMakerVocab{idS};
      sensorModel = a_ogSensorList.sensorModel{idS};
      sensorModelVocab = a_ogSensorList.sensorModelVocab{idS};
      sensorSerialNo = a_ogSensorList.sensorSerialNo{idS};
      sensorCalibDate = a_ogSensorList.sensorCalibDate{idS};
      if (isempty(sensorSerialNo))
         sensorSerialNo = '9999';
      end
      sensorType = upper(sensorType);
      sensorType = regexprep(sensorType, ' ', '_');
      varName = ['SENSOR_' sensorType '_' sensorSerialNo];
      if (~ismember(varName, ncParamNameList))
         sensorVarId = netcdf.defVar(fCdf, varName, 'NC_STRING', []);
         netcdf.putAtt(fCdf, sensorVarId, 'sensor_type_vocabulary', sensorTypeVocab);
         netcdf.putAtt(fCdf, sensorVarId, 'long_name', '');
         netcdf.putAtt(fCdf, sensorVarId, 'sensor_model', sensorModel);
         netcdf.putAtt(fCdf, sensorVarId, 'sensor_model_vocabulary', sensorModelVocab);
         netcdf.putAtt(fCdf, sensorVarId, 'sensor_maker', sensorMaker);
         netcdf.putAtt(fCdf, sensorVarId, 'sensor_maker_vocabulary', sensorMakerVocab);
         netcdf.putAtt(fCdf, sensorVarId, 'sensor_serial_number', sensorSerialNo);
         netcdf.putAtt(fCdf, sensorVarId, 'sensor_calibration_date', sensorCalibDate);
         ncParamNameList{end+1} = varName;
      end
   end

   % geophysical variables
   for idP = 1:length(a_ogParamList)
      ncParamName = a_ogParamList{idP};
      if (~ismember(ncParamName, ncParamNameList))

         % create geophysical variables that have not already set
         if ~((length(ncParamName) > 2) && strcmp(ncParamName(end-2:end), '_QC'))

            % create <PARAM> variable
            ncParamQcName = [ncParamName '_QC'];
            paramInfo = gl_get_og_var_attributes(ncParamName);
            if (~isempty(paramInfo))
               paramVarId = netcdf.defVar(fCdf, ncParamName, paramInfo.typeof, nMeasurementsDimId);
               netcdf.putAtt(fCdf, paramVarId, 'long_name', paramInfo.long_name);
               netcdf.putAtt(fCdf, paramVarId, 'standard_name', paramInfo.standard_name);
               netcdf.putAtt(fCdf, paramVarId, 'vocabulary', paramInfo.vocabulary);
               netcdf.putAtt(fCdf, paramVarId, '_FillValue', paramInfo.FillValue);
               netcdf.putAtt(fCdf, paramVarId, 'units', paramInfo.units);
               netcdf.putAtt(fCdf, paramVarId, 'ancillary_variables', ncParamQcName);
               netcdf.putAtt(fCdf, paramVarId, 'coordinates', 'TIME, LONGITUDE, LATITUDE, DEPTH');
               sensorAtt = '';
               sensorType = a_ogSensorList.sensorType{idP};
               sensorSerialNo = a_ogSensorList.sensorSerialNo{idP};
               if (isempty(sensorSerialNo))
                  sensorSerialNo = '9999';
               end
               if (~isempty(sensorType))
                  sensorType = upper(sensorType);
                  sensorType = regexprep(sensorType, ' ', '_');
                  sensorAtt = ['SENSOR_' sensorType '_' sensorSerialNo];
               end
               netcdf.putAtt(fCdf, paramVarId, 'sensor', sensorAtt);
               ncParamNameList{end+1} = ncParamName;
            else
               fprintf('ERROR: No information on OG parameter ''%s'' - parameter ignored\n', ncParamName);
               continue
            end
         else

            % create <PARAM>_QC variable
            paramQcVarId = netcdf.defVar(fCdf, ncParamName, 'NC_BYTE', nMeasurementsDimId);
            netcdf.putAtt(fCdf, paramQcVarId, 'long_name', 'quality flag');
            netcdf.putAtt(fCdf, paramQcVarId, '_FillValue', int8(' '));
            netcdf.putAtt(fCdf, paramQcVarId, 'valid_range', int8(0:4));
            netcdf.putAtt(fCdf, paramQcVarId, 'flag_values', int8(0:4));
            netcdf.putAtt(fCdf, paramQcVarId, 'flag_meanings', 'No QC has been applied, Good data, Probably good data, Probably bad data, Bad data');
            netcdf.putAtt(fCdf, paramQcVarId, 'RTQC_methodology', '');
            netcdf.putAtt(fCdf, paramQcVarId, 'RTQC_methodology_vocabulary', '');
            netcdf.putAtt(fCdf, paramQcVarId, 'RTQC_methodology_doi', '');
            ncParamNameList{end+1} = ncParamName;
         end
      end
   end

   %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
   % DEFINE MODE END

   netcdf.endDef(fCdf);

   % fill N_MEASUREMENTS variables
   ncParamDoneList = [];
   for idP = 1:length(a_ogParamList)
      ncParamName = a_ogParamList{idP};
      if (~ismember(ncParamName, ncParamDoneList))

         % fill geophysical variables
         if ~((length(ncParamName) > 2) && strcmp(ncParamName(end-2:end), '_QC'))

            % fill <PARAM> variable
            paramInfo = gl_get_og_var_attributes(ncParamName);
            if (~isempty(paramInfo))
               paramData = a_ogParamData(:, idP);
               idNoNan = find(~isnan(paramData));
               switch (paramInfo.typeof)
                  case 'NC_DOUBLE'
                     ncParamData = double(ones(size(paramData)))*double(paramInfo.FillValue);
                     ncParamData(idNoNan) = double(paramData(idNoNan));
                  case 'NC_FLOAT'
                     ncParamData = single(ones(size(paramData)))*single(paramInfo.FillValue);
                     ncParamData(idNoNan) = single(paramData(idNoNan));
                  case 'NC_BYTE'
                     ncParamData = int8(ones(size(paramData)))*int8(paramInfo.FillValue);
                     ncParamData(idNoNan) = int8(paramData(idNoNan));
                  otherwise
                     fprintf('ERROR: Not managed parameter (''%s'') type ''%s'' - data ignored\n', ncParamName, paramInfo.typeof);
                     continue
               end
               netcdf.putVar(fCdf, netcdf.inqVarID(fCdf, ncParamName), 0, length(ncParamData), ncParamData);
               ncParamDoneList{end+1} = ncParamName;
            else
               fprintf('ERROR: No information on OG parameter ''%s'' - parameter ignored\n', ncParamName);
               continue
            end
         else
            % fill <PARAM>_QC variable
            paramQcData = a_ogParamData(:, idP);
            idNoNan = find(~isnan(paramQcData));
            ncParamQcData = int8(ones(size(paramQcData)))*int8(' ');
            ncParamQcData(idNoNan) = int8(paramQcData(idNoNan));
            netcdf.putVar(fCdf, netcdf.inqVarID(fCdf, ncParamName), 0, length(ncParamQcData), ncParamQcData);
            ncParamDoneList{end+1} = ncParamName;
         end
      end
   end

   % fill trajectory name variable
   if (~isempty(a_ogTrajName.TRAJECTORY))
      netcdf.putVar(fCdf, trajectoryVarId, a_ogTrajName.TRAJECTORY);
   end

   % fill platform information variables
   if (~isempty(a_ogPlatformInfo.WMO_IDENTIFIER))
      netcdf.putVar(fCdf, wmoIdentifierVarId, a_ogPlatformInfo.WMO_IDENTIFIER);
   end
   if (~isempty(a_ogPlatformInfo.PLATFORM_MODEL))
      netcdf.putVar(fCdf, platformModelVarId, a_ogPlatformInfo.PLATFORM_MODEL);
   end
   if (~isempty(a_ogPlatformInfo.PLATFORM_SERIAL_NUMBER))
      netcdf.putVar(fCdf, platformSerialNumberVarId, a_ogPlatformInfo.PLATFORM_SERIAL_NUMBER);
   end
   if (~isempty(a_ogPlatformInfo.PLATFORM_NAME))
      netcdf.putVar(fCdf, platformNameVarId, a_ogPlatformInfo.PLATFORM_NAME);
   end
   if (~isempty(a_ogPlatformInfo.PLATFORM_DEPTH_RATING))
      netcdf.putVar(fCdf, platformDepthRatingVarId, a_ogPlatformInfo.PLATFORM_DEPTH_RATING);
   end
   if (~isempty(a_ogPlatformInfo.ICES_CODE))
      netcdf.putVar(fCdf, icesCodeVarId, a_ogPlatformInfo.ICES_CODE);
   end
   if (~isempty(a_ogPlatformInfo.PLATFORM_MAKER))
      netcdf.putVar(fCdf, platformMakerVarId, a_ogPlatformInfo.PLATFORM_MAKER);
   end

   % fill deployment information variables
   if (~isempty(a_ogDeployInfo.DEPLOYMENT_TIME))
      netcdf.putVar(fCdf, deploymentTimeVarId, a_ogDeployInfo.DEPLOYMENT_TIME);
   end
   if (~isempty(a_ogDeployInfo.DEPLOYMENT_LATITUDE))
      netcdf.putVar(fCdf, deploymentLatitudeVarId, a_ogDeployInfo.DEPLOYMENT_LATITUDE);
   end
   if (~isempty(a_ogDeployInfo.DEPLOYMENT_LONGITUDE))
      netcdf.putVar(fCdf, deploymentLongitudeVarId, a_ogDeployInfo.DEPLOYMENT_LONGITUDE);
   end

   % fill field comparison information variable
   if (~isempty(a_ogFieldCompRef.FIELD_COMPARISON_REFERENCE))
      netcdf.putVar(fCdf, fieldComparisonReferenceVarId, a_ogFieldCompRef.FIELD_COMPARISON_REFERENCE);
   end

   % fill hardware information variables
   if (~isempty(a_ogHardwareInfo.GLIDER_FIRMWARE_VERSION))
      netcdf.putVar(fCdf, gliderFirmwareVersionVarId, a_ogHardwareInfo.GLIDER_FIRMWARE_VERSION);
   end
   if (~isempty(a_ogHardwareInfo.LANDSTATION_VERSION))
      netcdf.putVar(fCdf, landstationVersionVarId, a_ogHardwareInfo.LANDSTATION_VERSION);
   end
   if (~isempty(a_ogHardwareInfo.BATTERY_TYPE))
      netcdf.putVar(fCdf, batteryTypeVarId, a_ogHardwareInfo.BATTERY_TYPE);
   end
   if (~isempty(a_ogHardwareInfo.BATTERY_PACK))
      netcdf.putVar(fCdf, batteryPackVarId, a_ogHardwareInfo.BATTERY_PACK);
   end

   % fill telecom information variables
   if (~isempty(a_ogTelecomInfo.TELECOM_TYPE))
      netcdf.putVar(fCdf, telecomTypeVarId, a_ogTelecomInfo.TELECOM_TYPE);
   end
   if (~isempty(a_ogTelecomInfo.TRACKING_SYSTEM))
      netcdf.putVar(fCdf, trackingSystemVarId, a_ogTelecomInfo.TRACKING_SYSTEM);
   end

   netcdf.close(fCdf);

% catch MException
% 
%    netcdf.close(fCdf);
% 
%    fprintf('ERROR:\n');
%    fprintf('%s\n', regexprep(MException.message, char(10), ': '));
%    for idS = 1:size(MException.stack, 1)
%       fprintf('Line: %3d File: %s (func: %s)\n', ...
%          MException.stack(idS). line, ...
%          MException.stack(idS). file, ...
%          MException.stack(idS). name);
%    end
% end

if (g_decGl_realtimeFlag == 1)
   % store information for the XML report
   g_decGl_reportStruct.outputFiles = [g_decGl_reportStruct.outputFiles ...
      {a_outFilePathName}];
end

return

% ------------------------------------------------------------------------------
% Get the basic structure to store OG global attributes information.
%
% SYNTAX :
%  [o_ogGlobalAttStruct] = gl_get_og_global_att_init_struct
%
% INPUT PARAMETERS :
%
% OUTPUT PARAMETERS :
%   o_ogGlobalAttStruct : OG global attributes structure
%
% EXAMPLES :
%
% SEE ALSO :
% AUTHOR : Jean-Philippe Rannou (Capgemini) (jean.philippe.rannou@partenaire-exterieur.ifremer.fr)
% ------------------------------------------------------------------------------
% RELEASES :
%   02/05/2025 - RNU - creation
% ------------------------------------------------------------------------------
function [o_ogGlobalAttStruct] = gl_get_og_global_att_init_struct

% output parameters initialization
o_ogGlobalAttStruct = struct( ...
   'title', '', ...
   'platform', '', ...
   'platform_vocabulary', '', ...
   'id', '', ...
   'naming_authority', '', ...
   'institution', '', ...
   'internal_mission_identifier', '', ...
   'geospatial_lat_min', '', ...
   'geospatial_lat_max', '', ...
   'geospatial_lon_min', '', ...
   'geospatial_lon_max', '', ...
   'geospatial_vertical_min', '', ...
   'geospatial_vertical_max', '', ...
   'time_coverage_start', '', ...
   'time_coverage_end', '', ...
   'site', '', ...
   'site_vocabulary', '', ...
   'program', '', ...
   'program_vocabulary', '', ...
   'project', '', ...
   'network', '', ...
   'contributor_name', '', ...
   'contributor_email', '', ...
   'contributor_id', '', ...
   'contributor_role', '', ...
   'contributor_role_vocabulary', '', ...
   'contributing_institutions', '', ...
   'contributing_institutions_vocabulary', '', ...
   'contributing_institutions_role', '', ...
   'contributing_institutions_role_vocabulary', '', ...
   'uri', '', ...
   'data_url', '', ...
   'doi', '', ...
   'rtqc_method', '', ...
   'rtqc_method_doi', '', ...
   'web_link', '', ...
   'comment', '', ...
   'start_date', '', ...
   'date_created', '', ...
   'featureType', '', ...
   'Conventions', '');

return

% ------------------------------------------------------------------------------
% Get the basic structure to store OG trajectory name information.
%
% SYNTAX :
%  [o_ogTrajNameStruct] = gl_get_og_traj_name_init_struct
%
% INPUT PARAMETERS :
%
% OUTPUT PARAMETERS :
%   o_ogTrajNameStruct : OG trajectory name structure
%
% EXAMPLES :
%
% SEE ALSO :
% AUTHOR : Jean-Philippe Rannou (Capgemini) (jean.philippe.rannou@partenaire-exterieur.ifremer.fr)
% ------------------------------------------------------------------------------
% RELEASES :
%   02/07/2025 - RNU - creation
% ------------------------------------------------------------------------------
function [o_ogTrajNameStruct] = gl_get_og_traj_name_init_struct

% output parameters initialization
o_ogTrajNameStruct = struct( ...
   'TRAJECTORY', '');

return

% ------------------------------------------------------------------------------
% Get the basic structure to store OG platform information.
%
% SYNTAX :
%  [o_ogPlatformInfoStruct] = gl_get_og_platform_info_init_struct
%
% INPUT PARAMETERS :
%
% OUTPUT PARAMETERS :
%   o_ogPlatformInfoStruct : OG platform information structure
%
% EXAMPLES :
%
% SEE ALSO :
% AUTHOR : Jean-Philippe Rannou (Capgemini) (jean.philippe.rannou@partenaire-exterieur.ifremer.fr)
% ------------------------------------------------------------------------------
% RELEASES :
%   02/07/2025 - RNU - creation
% ------------------------------------------------------------------------------
function [o_ogPlatformInfoStruct] = gl_get_og_platform_info_init_struct

% output parameters initialization
o_ogPlatformInfoStruct = struct( ...
   'WMO_IDENTIFIER', '', ...
   'PLATFORM_MODEL', '', ...
   'PLATFORM_SERIAL_NUMBER', '', ...
   'PLATFORM_NAME', '', ...
   'PLATFORM_DEPTH_RATING', '', ...
   'ICES_CODE', '', ...
   'PLATFORM_MAKER', '');

return

% ------------------------------------------------------------------------------
% Get the basic structure to store OG deployment information.
%
% SYNTAX :
%  [o_ogDeployInfoStruct] = gl_get_og_deploy_info_init_struct
%
% INPUT PARAMETERS :
%
% OUTPUT PARAMETERS :
%   o_ogDeployInfoStruct : OG deployment information structure
%
% EXAMPLES :
%
% SEE ALSO :
% AUTHOR : Jean-Philippe Rannou (Capgemini) (jean.philippe.rannou@partenaire-exterieur.ifremer.fr)
% ------------------------------------------------------------------------------
% RELEASES :
%   02/07/2025 - RNU - creation
% ------------------------------------------------------------------------------
function [o_ogDeployInfoStruct] = gl_get_og_deploy_info_init_struct

% output parameters initialization
o_ogDeployInfoStruct = struct( ...
   'DEPLOYMENT_TIME', '', ...
   'DEPLOYMENT_LATITUDE', '', ...
   'DEPLOYMENT_LONGITUDE', '');

return

% ------------------------------------------------------------------------------
% Get the basic structure to store OG field comparison reference.
%
% SYNTAX :
%  [o_ogFieldCompRefStruct] = gl_get_og_field_comp_ref_init_struct
%
% INPUT PARAMETERS :
%
% OUTPUT PARAMETERS :
%   o_ogFieldCompRefStruct : OG field comparison reference structure
%
% EXAMPLES :
%
% SEE ALSO :
% AUTHOR : Jean-Philippe Rannou (Capgemini) (jean.philippe.rannou@partenaire-exterieur.ifremer.fr)
% ------------------------------------------------------------------------------
% RELEASES :
%   02/07/2025 - RNU - creation
% ------------------------------------------------------------------------------
function [o_ogFieldCompRefStruct] = gl_get_og_field_comp_ref_init_struct

% output parameters initialization
o_ogFieldCompRefStruct = struct( ...
   'FIELD_COMPARISON_REFERENCE', '');

return

% ------------------------------------------------------------------------------
% Get the basic structure to store OG hardware information.
%
% SYNTAX :
%  [o_ogHardwareInfoStruct] = gl_get_og_hardware_info_init_struct
%
% INPUT PARAMETERS :
%
% OUTPUT PARAMETERS :
%   o_ogHardwareInfoStruct : OG hardware information structure
%
% EXAMPLES :
%
% SEE ALSO :
% AUTHOR : Jean-Philippe Rannou (Capgemini) (jean.philippe.rannou@partenaire-exterieur.ifremer.fr)
% ------------------------------------------------------------------------------
% RELEASES :
%   02/07/2025 - RNU - creation
% ------------------------------------------------------------------------------
function [o_ogHardwareInfoStruct] = gl_get_og_hardware_info_init_struct

% output parameters initialization
o_ogHardwareInfoStruct = struct( ...
   'GLIDER_FIRMWARE_VERSION', '', ...
   'LANDSTATION_VERSION', '', ...
   'BATTERY_TYPE', '', ...
   'BATTERY_PACK', '');

return

% ------------------------------------------------------------------------------
% Get the basic structure to store OG telecom information.
%
% SYNTAX :
%  [o_ogTelecomInfoStruct] = gl_get_og_telecom_info_init_struct
%
% INPUT PARAMETERS :
%
% OUTPUT PARAMETERS :
%   o_ogTelecomInfoStruct : OG telecom information structure
%
% EXAMPLES :
%
% SEE ALSO :
% AUTHOR : Jean-Philippe Rannou (Capgemini) (jean.philippe.rannou@partenaire-exterieur.ifremer.fr)
% ------------------------------------------------------------------------------
% RELEASES :
%   02/07/2025 - RNU - creation
% ------------------------------------------------------------------------------
function [o_ogTelecomInfoStruct] = gl_get_og_telecom_info_init_struct

% output parameters initialization
o_ogTelecomInfoStruct = struct( ...
   'TELECOM_TYPE', '', ...
   'TRACKING_SYSTEM', '');

return
