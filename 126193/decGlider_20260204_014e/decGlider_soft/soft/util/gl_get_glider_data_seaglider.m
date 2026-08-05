% ------------------------------------------------------------------------------
% Check seaglider glider data file contents and usage.
%
% SYNTAX :
%   gl_get_glider_data_seaglider or
%   gl_get_glider_data_seaglider('data', 'crate_mooset00_38')
%
% INPUT PARAMETERS :
%   varargin : input arguments
%      must be provided in pairs i.e. ('argument_name', 'argument_value')
%      expected argument names:
%      'data' : identify the deployment (i.e. the sub-directory of the
%               DATA_DIRECTORY directory) to process
%      if no argument is provided: all the deployments of the
%      DATA_DIRECTORY directory are processed
%
% OUTPUT PARAMETERS :
%
% EXAMPLES :
%
% SEE ALSO :
% AUTHOR : Jean-Philippe Rannou (Capgemini) (jean.philippe.rannou@partenaire-exterieur.ifremer.fr)
% ------------------------------------------------------------------------------
% RELEASES :
%   10/25/2023 - RNU - creation
% ------------------------------------------------------------------------------
function gl_get_glider_data_seaglider(varargin)

% top directory of the deployment directories
DATA_DIRECTORY = 'C:\Users\jprannou\_DATA\GLIDER\seaglider\';

% directory to store the log file
DIR_LOG_FILE = 'C:\Users\jprannou\_RNU\Glider\work\log\';

% directory to store the CSV file
DIR_CSV_FILE = 'C:\Users\jprannou\_RNU\Glider\work\csv\';

% available data mat file
AVAILABLE_DATA_FILE_NAME = 'C:\Users\jprannou\_RNU\Glider\work\seaglider_available_data.mat';

% default values initialization
gl_init_default_values;


% check configuration information
if ~(exist(DATA_DIRECTORY, 'dir') == 7)
   fprintf('ERROR: ''DATA_DIRECTORY'' directory not found: %s\n', DATA_DIRECTORY);
   return
end

if ~(exist(DIR_LOG_FILE, 'dir') == 7)
   fprintf('ERROR: ''DIR_LOG_FILE'' directory not found: %s\n', DIR_LOG_FILE);
   return
end

if ~(exist(DIR_CSV_FILE, 'dir') == 7)
   fprintf('ERROR: ''DIR_CSV_FILE'' directory not found: %s\n', DIR_CSV_FILE);
   return
end

% check input arguments
deploymentDir = [];
if (nargin > 0)
   if (rem(nargin, 2) ~= 0)
      fprintf('ERROR: expecting an even number of input arguments (e.g. (''argument_name'', ''argument_value'') => exit\n');
      diary off;
      return
   else
      for id = 1:2:nargin
         if (strcmpi(varargin{id}, 'data'))
            if (exist([DATA_DIRECTORY '/' varargin{id+1}], 'dir'))
               deploymentDir = varargin{id+1};
            else
               fprintf('WARNING: %s is not an existing directory => ignored\n', varargin{id+1});
               return
            end
         else
            fprintf('WARNING: unexpected input argument (%s) => ignored\n', varargin{id});
         end
      end
   end
end

% create and start log file recording
logFile = [DIR_LOG_FILE '/' 'gl_get_glider_data_seaglider_' deploymentDir '_' datestr(now, 'yyyymmddTHHMMSS') '.log'];
diary(logFile);
tic;

% create the CSV output file
outputFileName = [DIR_CSV_FILE '/' 'gl_get_glider_data_seaglider_' deploymentDir '_' datestr(now, 'yyyymmddTHHMMSS') '.csv'];
fidOut = fopen(outputFileName, 'wt');
if (fidOut == -1)
   return
end
header = 'DEPLOYMENT;DATA TYPE;GLIDER PARAMETER;GLIDER PARAMETER DIM;AVAILABLE DATA;JSON FILE;EGO PARAMETER;EGO SENSOR;EGO SENSOR_MAKER;EGO SENSOR_MODEL;EGO SENSOR_SERIAL_NO;PROCESSING ID';
fprintf(fidOut, '%s\n', header);

% check glider deployment
if (isempty(deploymentDir))
   % check all the deployments of the DATA_DIRECTORY directory
   dirInfo = dir(DATA_DIRECTORY);
   for dirNum = 1:length(dirInfo)
      if ~(strcmp(dirInfo(dirNum).name, '.') || strcmp(dirInfo(dirNum).name, '..'))
         dirName = dirInfo(dirNum).name;

         gl_check_deployment_data(DATA_DIRECTORY, dirName, AVAILABLE_DATA_FILE_NAME, fidOut);
      end
   end
else
   % check the data of this deployment
   gl_check_deployment_data(DATA_DIRECTORY, deploymentDir, AVAILABLE_DATA_FILE_NAME, fidOut);
end

fclose(fidOut);

ellapsedTime = toc;
fprintf('done (Elapsed time is %.1f seconds)\n', ellapsedTime);

diary off;

return

% ------------------------------------------------------------------------------
% Check glider data file contents and usage.
%
% SYNTAX :
% gl_check_deployment_data(a_deploymentTopDirName, a_deploymentDirName, ...
%   a_availableDataFile, a_csvFid)
%
% INPUT PARAMETERS :
%   a_deploymentTopDirName : top directory of deployments directory
%   a_deploymentDirName    : directory of the deployment
%   a_availableDataFile    : file of already checked available data
%   a_csvFid               : output CSv file Id
%
% OUTPUT PARAMETERS :
%
% EXAMPLES :
%
% SEE ALSO :
% AUTHOR : Jean-Philippe Rannou (Capgemini) (jean.philippe.rannou@partenaire-exterieur.ifremer.fr)
% ------------------------------------------------------------------------------
% RELEASES :
%   10/24/2023 - RNU - creation
% ------------------------------------------------------------------------------
function gl_check_deployment_data(a_deploymentTopDirName, a_deploymentDirName, ...
   a_availableDataFile, a_csvFid)

fprintf('Processing deployment: %s\n', a_deploymentDirName);

% retrieve glider parameter names and associated available data

availDataStruct = [];
found = 0;
if (exist(a_availableDataFile, 'file') == 2)
   info = load(a_availableDataFile);
   availDataStruct = info.availDataStruct;
   clear info
   idF = find(strcmp(a_deploymentDirName, {availDataStruct.deployName}));
   if (~isempty(idF))
      dataType = availDataStruct(idF).dataType;
      availableParam = availDataStruct(idF).gliderParam;
      availableParamDim = availDataStruct(idF).gliderParamDim;
      availableData = availDataStruct(idF).gliderData;
      availableCoef = availDataStruct(idF).gliderCoef;
      availableCoefV = availDataStruct(idF).gliderCoefValue;
      found = 1;
   end
end

if (~found)
   [availableParam, availableParamDim, availableData, ...
      availableCoef, availableCoefV, dataType] = ...
      gl_get_available_data_seaglider(a_deploymentTopDirName, a_deploymentDirName);
   aDataStruct = '';
   aDataStruct.deployName = a_deploymentDirName;
   aDataStruct.dataType = dataType;
   aDataStruct.gliderParam = availableParam;
   aDataStruct.gliderParamDim = availableParamDim;
   aDataStruct.gliderData = availableData;
   aDataStruct.gliderCoef = availableCoef;
   aDataStruct.gliderCoefValue = availableCoefV;
   if (isempty(availDataStruct))
      availDataStruct = aDataStruct;
   else
      availDataStruct(end+1) = aDataStruct;
   end
   save(a_availableDataFile, 'availDataStruct');
end

if (isempty(availableParam))
   fprintf('WARNING: no available parameters in deployment: %s\n', a_deploymentDirName);
   return
end

% retrieve Glider to EGO links
[sensorNames, paramNames, gliderNames, processingIds, ...
   sensorMaker, sensorModel, sensorSerialNo, jsonFile] = get_link_to_data(a_deploymentTopDirName, a_deploymentDirName);

for idP = 1:length(availableParam)
   idF = cellfun(@(x) strfind(gliderNames, x), availableParam(idP), 'UniformOutput', 0);
   if (~isempty(idF{:}))
      idF = find(~cellfun(@isempty, idF{:}));
      if (isempty(idF))
         fprintf(a_csvFid, '%s;%s;%s;%s;%d\n', ...
            a_deploymentDirName, dataType, ...
            availableParam{idP}, availableParamDim{idP}, availableData(idP) ...
            );
      else
         if (length(idF) > 1)
            idF1 = find(strcmp(gliderNames, availableParam(idP)));
            if (length(idF1) == 1)
               idF = idF1;
            else
               fprintf('ERROR\n');
            end
         end
         fprintf(a_csvFid, '%s;%s;%s;%s;%d;%s;%s;%s;%s;%s;%s\n', ...
            a_deploymentDirName, dataType, ...
            availableParam{idP}, availableParamDim{idP}, availableData(idP), ...
            jsonFile{idF}, paramNames{idF}, sensorNames{idF}, ...
            sensorMaker{idF}, sensorModel{idF}, sensorSerialNo{idF} ...
            );
      end
   else
      fprintf(a_csvFid, '%s;%s;%s;%s;%d\n', ...
         a_deploymentDirName, dataType, ...
         availableParam{idP}, availableParamDim{idP}, availableData(idP) ...
         );
   end
end

for idP = 1:length(gliderNames)
   if (isempty(gliderNames{idP}))
      fprintf(a_csvFid, '%s;%s;none;same as input;-1;%s;%s;%s;%s;%s;%s;%s\n', ...
         a_deploymentDirName, dataType, ...
         jsonFile{idP}, paramNames{idP}, sensorNames{idP}, ...
         sensorMaker{idP}, sensorModel{idP}, sensorSerialNo{idP}, processingIds{idP} ...
         );
   end
end

% check useless links
% for idP = 1:length(gliderNames)
%    if (~isempty(gliderNames{idP}))
%       idF = find(strcmp(gliderNames{idP}, availableParam));
%       if (isempty(idF))
%          fprintf('WARNING: ''%s'' useless link to ''%s'' - not in glider list\n', ...
%             paramNames{idP}, gliderNames{idP});
%       else
%          if (availableData(idF) == 0)
%             fprintf('WARNING: ''%s'' useless link to ''%s'' - no data in the deployment\n', ...
%                paramNames{idP}, gliderNames{idP});
%          end
%       end
%    end
% end

return

% ------------------------------------------------------------------------------
% Retrieve EGO to glider parameter link.
%
% SYNTAX :
% [o_sensorName, o_paramName, o_gliderName, o_processingId, ...
%   o_sensorMaker, o_sensorModel, o_sensorSerialNo, o_jsonFile] = get_link_to_data( ...
%   a_deploymentTopDirName, a_deploymentDirName)
%
% INPUT PARAMETERS :
%   a_deploymentTopDirName : top directory of deployments directory
%   a_deploymentDirName    : directory of the deployment
%
% OUTPUT PARAMETERS :
%   o_sensorName     : list of sensor names
%   o_paramName      : list of EGO parameter names
%   o_gliderName     : list of glider parameter names
%   o_processingId   : list of parameter processing Id
%   o_sensorMaker    : list of glider sensor maker
%   o_sensorModel    : list of glider sensor models
%   o_sensorSerialNo : list of glider sensor serial numbers
%   o_jsonFile       : list of glider JSON sensor file
%
% EXAMPLES :
%
% SEE ALSO :
% AUTHOR : Jean-Philippe Rannou (Capgemini) (jean.philippe.rannou@partenaire-exterieur.ifremer.fr)
% ------------------------------------------------------------------------------
% RELEASES :
%   10/24/2023 - RNU - creation
% ------------------------------------------------------------------------------
function [o_sensorName, o_paramName, o_gliderName, o_processingId, ...
   o_sensorMaker, o_sensorModel, o_sensorSerialNo, o_jsonFile] = get_link_to_data( ...
   a_deploymentTopDirName, a_deploymentDirName)

% output parameters initialization
o_sensorName = [];
o_paramName = [];
o_gliderName = [];
o_processingId = [];
o_sensorMaker = [];
o_sensorModel = [];
o_sensorSerialNo = [];
o_jsonFile = [];

% version of EGO format to be generated
global g_decGl_egoFormatVersion;


% directory of JSON files
jsonDirectory = [a_deploymentTopDirName '/' a_deploymentDirName '/json/'];
if (exist(jsonDirectory, 'dir') == 7)

   % JSON deployment file
   jsonInputPathFile = [a_deploymentTopDirName '/' a_deploymentDirName '/json/' a_deploymentDirName '.json'];
   if ~(~exist(jsonInputPathFile, 'dir') && exist(jsonInputPathFile, 'file'))
      fprintf('ERROR: expected json deployment file not found (%s) => deployment ignored\n', ...
         jsonInputPathFile);
      return
   end

   % retrieve sensor files
   metaData = gl_load_json(jsonInputPathFile);
   if ~(isfield(metaData, 'EGO_format_version') && ...
         ~isempty(metaData.EGO_format_version) && ...
         (str2double(metaData.EGO_format_version) == g_decGl_egoFormatVersion))
      fprintf('ERROR: expected ''%.1f'' EGO format version in json file (%s)\n', ...
         g_decGl_egoFormatVersion, jsonInputPathFile);
      return
   end
   sensorFileNames = [];
   if (isfield(metaData, 'glider_sensor'))
      for idFile = 1:length(metaData.glider_sensor)
         sensorFileNames{end+1} = metaData.glider_sensor(idFile).sensor_file_name;
      end
   end

   % retrieve parameters
   tabSensorInfo = [];
   tabGliderParam = [];
   tabEGOParam = [];
   tabProcessingId = [];
   tabSensorMaker = [];
   tabSensorModel = [];
   tabSensorSerialNo = [];
   tabJsonFile = [];
   for idFile = 1:length(sensorFileNames)
      jsonSensorPathFile = [a_deploymentTopDirName '/' a_deploymentDirName '/json/' sensorFileNames{idFile}];
      if ~(~exist(jsonSensorPathFile, 'dir') && exist(jsonSensorPathFile, 'file'))
         fprintf('ERROR: expected json sensor file not found (%s) => deployment ignored\n', ...
            jsonSensorPathFile);
         return
      end

      sensorData = gl_load_json(jsonSensorPathFile);
      if ~(isfield(sensorData, 'EGO_format_version') && ...
            ~isempty(sensorData.EGO_format_version) && ...
            (str2double(sensorData.EGO_format_version) == g_decGl_egoFormatVersion))
         fprintf('ERROR: expected ''%.1f'' EGO format version in json file (%s)\n', ...
            g_decGl_egoFormatVersion, jsonSensorPathFile);
         return
      end
      paramTab = sensorData.PARAMETER;
      if (ischar(paramTab) && (size(paramTab, 1) > 1))
         paramTab = cellstr(paramTab)';
      end
      paramSensorTab = sensorData.PARAMETER_SENSOR;
      if (ischar(paramSensorTab) && (size(paramSensorTab, 1) > 1))
         paramSensorTab = cellstr(paramSensorTab)';
      end
      sensorTab = sensorData.SENSOR;
      if (ischar(sensorTab) && (size(sensorTab, 1) > 1))
         sensorTab = cellstr(sensorTab)';
      end
      sensorMakerTab = sensorData.SENSOR_MAKER;
      if (ischar(sensorMakerTab) && (size(sensorMakerTab, 1) > 1))
         sensorMakerTab = cellstr(sensorMakerTab)';
      end
      sensorModelTab = sensorData.SENSOR_MODEL;
      if (ischar(sensorModelTab) && (size(sensorModelTab, 1) > 1))
         sensorModelTab = cellstr(sensorModelTab)';
      end
      sensorSerialNoTab = sensorData.SENSOR_SERIAL_NO;
      if (ischar(sensorSerialNoTab) && (size(sensorSerialNoTab, 1) > 1))
         sensorSerialNoTab = cellstr(sensorSerialNoTab)';
      end
      parameters = sensorData.parametersList;
      for idP = 1:length(parameters)
         if (iscell(parameters))
            paramData = parameters{idP};
         else
            paramData = parameters(idP);
         end
         glider_variable_name = paramData.glider_variable_name;
         idPoint = strfind(glider_variable_name, '.');
         if (~isempty(idPoint))
            glider_variable_name = glider_variable_name(idPoint(end)+1:end);
         end
         idF = find(strcmp(paramData.ego_variable_name, paramTab));
         tabSensorInfo{end+1} = paramSensorTab{idF};
         tabGliderParam{end+1} = strtrim(glider_variable_name);
         tabEGOParam{end+1} = strtrim(paramData.ego_variable_name);
         tabProcessingId{end+1} = strtrim(paramData.processing_id);
         idF = find(strcmp(paramSensorTab{idF}, sensorTab));
         tabSensorMaker{end+1} = sensorMakerTab{idF};
         tabSensorModel{end+1} = sensorModelTab{idF};
         tabSensorSerialNo{end+1} = sensorSerialNoTab{idF};
         tabJsonFile{end+1} = sensorFileNames{idFile};
         if (isfield(paramData, 'glider_adjusted_variable_name') && ~isempty(paramData.glider_adjusted_variable_name))
            glider_variable_name = paramData.glider_adjusted_variable_name;
            idPoint = strfind(glider_variable_name, '.');
            if (~isempty(idPoint))
               glider_variable_name = glider_variable_name(idPoint(end)+1:end);
            end
            idF = find(strcmp(paramData.ego_variable_name, paramTab));
            tabSensorInfo{end+1} = paramSensorTab{idF};
            tabGliderParam{end+1} = strtrim(glider_variable_name);
            tabEGOParam{end+1} = [strtrim(paramData.ego_variable_name) '_ADJUSTED'];
            tabProcessingId{end+1} = strtrim(paramData.processing_id);
            idF = find(strcmp(paramSensorTab{idF}, sensorTab));
            tabSensorMaker{end+1} = sensorMakerTab{idF};
            tabSensorModel{end+1} = sensorModelTab{idF};
            tabSensorSerialNo{end+1} = sensorSerialNoTab{idF};
            tabJsonFile{end+1} = sensorFileNames{idFile};
         end
      end
   end

   o_sensorName = tabSensorInfo;
   o_paramName = tabEGOParam;
   o_gliderName = tabGliderParam;
   o_processingId = tabProcessingId;
   o_sensorMaker = tabSensorMaker;
   o_sensorModel = tabSensorModel;
   o_sensorSerialNo = tabSensorSerialNo;
   o_jsonFile = tabJsonFile;

else
   fprintf('WARNING: directory not found: %s\n', jsonDirectory);
   return
end

return
