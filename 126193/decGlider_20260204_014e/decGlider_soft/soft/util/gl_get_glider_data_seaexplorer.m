% ------------------------------------------------------------------------------
% Retrieve seaexplorer data file contents.
%
% SYNTAX :
%   gl_get_glider_data_seaexplorer or
%   gl_get_glider_data_seaexplorer('data', 'crate_mooset00_38')
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
%   10/31/2023 - RNU - creation
% ------------------------------------------------------------------------------
function gl_get_glider_data_seaexplorer(varargin)

% top directory of the deployment directories
DATA_DIRECTORY = 'C:\Users\jprannou\_DATA\GLIDER\seaexplorer\';

% directory to store the log file
DIR_LOG_FILE = 'C:\Users\jprannou\_RNU\Glider\work\log\';

% directory to store the CSV file
DIR_CSV_FILE = 'C:\Users\jprannou\_RNU\Glider\work\csv\';

% available data mat file
AVAILABLE_DATA_FILE_NAME = 'C:\Users\jprannou\_RNU\Glider\work\seaexplorer_available_data.mat';

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
logFile = [DIR_LOG_FILE '/' 'gl_get_glider_data_seaexplorer_' deploymentDir '_' datestr(now, 'yyyymmddTHHMMSS') '.log'];
diary(logFile);
tic;

% create the CSV output file
outputFileName = [DIR_CSV_FILE '/' 'gl_get_glider_data_seaexplorer_' deploymentDir '_' datestr(now, 'yyyymmddTHHMMSS') '.csv'];
fidOut = fopen(outputFileName, 'wt');
if (fidOut == -1)
   return
end
header = 'DEPLOYMENT;GLIDER PARAMETER;AVAILABLE DATA;JSON FILE;EGO PARAMETER;EGO SENSOR;EGO SENSOR_MAKER;EGO SENSOR_MODEL;EGO SENSOR_SERIAL_NO;PROCESSING_ID';
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
% Retrieve glider data file contents.
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
%   10/31/2023 - RNU - creation
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
      availableParam = availDataStruct(idF).gliderParam;
      availableData = availDataStruct(idF).gliderData;
      found = 1;
   end
end

if (~found)
   [availableParam, availableData] = gl_get_available_data_seaexplorer(a_deploymentTopDirName, a_deploymentDirName);
   aDataStruct = '';
   aDataStruct.deployName = a_deploymentDirName;
   aDataStruct.gliderParam = availableParam;
   aDataStruct.gliderData = availableData;
   if (isempty(availDataStruct))
      availDataStruct = aDataStruct;
   else
      availDataStruct(end+1) = aDataStruct;
   end
   save(a_availableDataFile, 'availDataStruct');
end

if (isempty(availableParam))
   fprintf('WARNING: no available parameters in deployment: %s\n', a_deploymentDirName);
end

% retrieve Glider to EGO links
paramListStruct = get_link_to_data(a_deploymentTopDirName, a_deploymentDirName);

gliderVarNames = {paramListStruct.glider_variable_name};
for idP = 1:length(availableParam)
   idF = cellfun(@(x) strfind(gliderVarNames, x), availableParam(idP), 'UniformOutput', 0);
   if (~isempty(idF{:}))
      idF = find(~cellfun(@isempty, idF{:}));
      if (isempty(idF))
         fprintf(a_csvFid, '%s;%s;%d\n', ...
            a_deploymentDirName, ...
            availableParam{idP}, availableData(idP) ...
            );
      else
         fprintf(a_csvFid, '%s;%s;%d;%s;%s;%s;%s;%s;%s;%s\n', ...
            a_deploymentDirName, ...
            availableParam{idP}, availableData(idP), ...
            paramListStruct(idF).json_file, ...
            paramListStruct(idF).ego_variable_name, ...
            paramListStruct(idF).sensor, ...
            paramListStruct(idF).sensor_maker, ...
            paramListStruct(idF).sensor_model, ...
            paramListStruct(idF).sensor_serial_no, ...
            paramListStruct(idF).processing_id ...
            );
      end
   else
      fprintf(a_csvFid, '%s;%s;%d\n', ...
         a_deploymentDirName, ...
         availableParam{idP}, availableData(idP) ...
         );
   end
end

for idP = 1:length(gliderVarNames)
   if (isempty(gliderVarNames{idP}))
      fprintf(a_csvFid, '%s;none;-1;%s;%s;%s;%s;%s;%s;%s\n', ...
         a_deploymentDirName, ...
         paramListStruct(idP).json_file, ...
         paramListStruct(idP).ego_variable_name, ...
         paramListStruct(idP).sensor, ...
         paramListStruct(idP).sensor_maker, ...
         paramListStruct(idP).sensor_model, ...
         paramListStruct(idP).sensor_serial_no, ...
         paramListStruct(idP).processing_id ...
         );
   end
end

return

% ------------------------------------------------------------------------------
% Retrieve EGO to glider parameter link.
%
% SYNTAX :
% [o_paramListStruct] = get_link_to_data(a_deploymentTopDirName, a_deploymentDirName)
%
% INPUT PARAMETERS :
%   a_deploymentTopDirName : top directory of deployments directory
%   a_deploymentDirName    : directory of the deployment
%
% OUTPUT PARAMETERS :
%   o_paramListStruct : information on list of glider parameters
%
% EXAMPLES :
%
% SEE ALSO :
% AUTHOR : Jean-Philippe Rannou (Capgemini) (jean.philippe.rannou@partenaire-exterieur.ifremer.fr)
% ------------------------------------------------------------------------------
% RELEASES :
%   12/05/2023 - RNU - creation
% ------------------------------------------------------------------------------
function [o_paramListStruct] = get_link_to_data(a_deploymentTopDirName, a_deploymentDirName)

% output parameters initialization
o_paramListStruct = [];

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
      paramDataModeTab = sensorData.PARAMETER_DATA_MODE;
      if (ischar(paramDataModeTab) && (size(paramDataModeTab, 1) > 1))
         paramDataModeTab = cellstr(paramDataModeTab)';
      end
      paramUnitsTab = sensorData.PARAMETER_UNITS;
      if (ischar(paramUnitsTab) && (size(paramUnitsTab, 1) > 1))
         paramUnitsTab = cellstr(paramUnitsTab)';
      end
      paramAccuracyTab = sensorData.PARAMETER_ACCURACY;
      if (ischar(paramAccuracyTab) && (size(paramAccuracyTab, 1) > 1))
         paramAccuracyTab = cellstr(paramAccuracyTab)';
      end
      paramResolutionTab = sensorData.PARAMETER_RESOLUTION;
      if (ischar(paramResolutionTab) && (size(paramResolutionTab, 1) > 1))
         paramResolutionTab = cellstr(paramResolutionTab)';
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
      sensorMountTab = sensorData.SENSOR_MOUNT;
      if (ischar(sensorMountTab) && (size(sensorMountTab, 1) > 1))
         sensorMountTab = cellstr(sensorMountTab)';
      end
      sensorOrientationTab = sensorData.SENSOR_ORIENTATION;
      if (ischar(sensorOrientationTab) && (size(sensorOrientationTab, 1) > 1))
         sensorOrientationTab = cellstr(sensorOrientationTab)';
      end

      parameters = sensorData.parametersList;
      for idP = 1:length(parameters)
         if (iscell(parameters))
            paramData = parameters{idP};
         else
            paramData = parameters(idP);
         end

         paramStruct = [];
         paramStruct.ego_variable_name = paramData.ego_variable_name;
         paramStruct.glider_variable_name = paramData.glider_variable_name;
         paramStruct.comment = paramData.comment;
         paramStruct.cell_methods = paramData.cell_methods;
         paramStruct.reference_scale = paramData.reference_scale;
         paramStruct.derivation_equation = paramData.derivation_equation;
         paramStruct.derivation_coefficient = paramData.derivation_coefficient;
         paramStruct.derivation_comment = paramData.derivation_comment;
         paramStruct.derivation_date = paramData.derivation_date;
         paramStruct.processing_id = paramData.processing_id;

         idParam = find(strcmp(paramData.ego_variable_name, paramTab));
         paramStruct.param_data_mode = paramDataModeTab{idParam};
         paramStruct.param_units = paramUnitsTab{idParam};
         paramStruct.param_accuracy = paramAccuracyTab{idParam};
         paramStruct.param_resolution = paramResolutionTab{idParam};

         idSensor = find(strcmp(paramSensorTab{idParam}, sensorTab));
         paramStruct.sensor = sensorTab{idSensor};
         paramStruct.sensor_maker = sensorMakerTab{idSensor};
         paramStruct.sensor_model = sensorModelTab{idSensor};
         paramStruct.sensor_serial_no = sensorSerialNoTab{idSensor};
         paramStruct.sensor_mount = sensorMountTab{idSensor};
         paramStruct.sensor_orientation = sensorOrientationTab{idSensor};

         paramStruct.json_file = sensorFileNames{idFile};

         o_paramListStruct = [o_paramListStruct paramStruct];
      end      
   end
else
   fprintf('WARNING: directory not found: %s\n', jsonDirectory);
   return
end

return
