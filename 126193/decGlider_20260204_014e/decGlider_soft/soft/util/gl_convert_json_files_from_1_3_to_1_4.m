% ------------------------------------------------------------------------------
% Convert JSON deployment and sensor files from EGO 1.3 to EGO 1.4.
% The default behaviour is :
%    - to process all the deployments (the directories) stored in the
%      DATA_DIRECTORY directory
% this behaviour can be modified by input arguments.
%
% SYNTAX :
%   gl_convert_json_files_from_1_3_to_1_4(varargin)
%
% INPUT PARAMETERS :
%   varargin : input arguments 
%      must be provided in pairs i.e. ('argument_name', 'argument_value')
%      expected argument names:
%      'data' : identify the deployment (i.e. the sub-directory of the
%               DATA_DIRECTORY directory) to process
%
% OUTPUT PARAMETERS :
%
% EXAMPLES :
%
% SEE ALSO :
% AUTHOR : Jean-Philippe Rannou (Capgemini) (jean.philippe.rannou@partenaire-exterieur.ifremer.fr)
% ------------------------------------------------------------------------------
% RELEASES :
%   07/29/2023 - RNU - creation
% ------------------------------------------------------------------------------
function gl_convert_json_files_from_1_3_to_1_4(varargin)

% top directory of the deployment directories
% DATA_DIRECTORY = 'C:\Users\jprannou\_DATA\GLIDER\FORMAT_1.4/';
% DATA_DIRECTORY = 'E:\GLIDER\seaglider/';
% DATA_DIRECTORY = 'E:\GLIDER\seaexplorer/';
% DATA_DIRECTORY = 'E:\GLIDER\slocum/';
DATA_DIRECTORY = 'C:\Users\jprannou\_DATA\GLIDER\slocum/';
DATA_DIRECTORY = 'C:\Users\jprannou\_DATA\GLIDER\seaglider/';
DATA_DIRECTORY = 'C:\Users\jprannou\_DATA\GLIDER\seaexplorer/';

% directory to store log files
DIR_LOG_FILE = 'C:\Users\jprannou\_RNU\Glider\work\log\';

% reference file for JSON deployment file
JSON_DEPLOYMENT_REF_FILE = 'C:\Users\jprannou\_RNU\Glider\soft\util\json\deployment_ref_1_4.json';

% reference file for JSON sensor file
JSON_SENSOR_REF_FILE = 'C:\Users\jprannou\_RNU\Glider\soft\util\json\sensor_ref_1_4.json';

% default values initialization
gl_init_default_values;


% create and start log file recording
logFile = [DIR_LOG_FILE '/' 'gl_convert_json_files_from_1_3_to_1_4_' datestr(now, 'yyyymmddTHHMMSS') '.log'];
diary(logFile);
tic;

% check input arguments
dataToProcessDir = '';
stop = 0;
if (nargin > 0)
   if (rem(nargin, 2) ~= 0)
      fprintf('ERROR: expecting an even number of input arguments (e.g. (''argument_name'', ''argument_value'') => exit\n');
      diary off;
      return
   else
      for id = 1:2:nargin
         if (strcmpi(varargin{id}, 'data'))
            dataToProcessDir = [DATA_DIRECTORY '/' varargin{id+1} '/'];
            deploymentDirName = varargin{id+1};
            if (~exist(dataToProcessDir, 'dir'))
               fprintf('ERROR: %s is not an existing directory => exit\n', varargin{id+1});
               stop = 1;
            end
         else
            fprintf('WARNING: unexpected input argument (%s) => ignored\n', varargin{id});
         end
      end
   end
end
if (stop)
   return
end

% print the arguments understanding
if (isempty(dataToProcessDir))
   fprintf('INFO: process all the deployments of the %s directory\n', DATA_DIRECTORY);
else
   fprintf('INFO: process the deployment stored in the %s directory\n', dataToProcessDir);
end

% process glider data
if (isempty(dataToProcessDir))
   % process all the deployments of the DATA_DIRECTORY directory
   dirInfo = dir(DATA_DIRECTORY);
   for dirNum = 1:length(dirInfo)
      if ~(strcmp(dirInfo(dirNum).name, '.') || strcmp(dirInfo(dirNum).name, '..'))
         dirName = dirInfo(dirNum).name;
         
         % process the data of this deployment
         gl_convert_json_files( ...
            [DATA_DIRECTORY '/' dirName '/'], ...
            dirName, ...
            JSON_DEPLOYMENT_REF_FILE, ...
            JSON_SENSOR_REF_FILE);
      end
   end
else
   % process the data of this deployment
   gl_convert_json_files( ...
      dataToProcessDir, ...
      deploymentDirName, ...
      JSON_DEPLOYMENT_REF_FILE, ...
      JSON_SENSOR_REF_FILE);
end

ellapsedTime = toc;
fprintf('done (Elapsed time is %.1f seconds)\n', ellapsedTime);

diary off;

return

% ------------------------------------------------------------------------------
% Convert JSON deployment and sensor files from EGO 1.2 to EGO 1.3.
%
% SYNTAX :
%  gl_convert_json_files(a_deploymentDirName, a_deploymentName, ...
%    a_jsonDeploymentRefFile, a_jsonSensorRefFile)
%
% INPUT PARAMETERS :
%   a_deploymentDirName     : name of the deployment directory
%   a_deploymentName        : name of the deployment
%   a_jsonDeploymentRefFile : json deployment reference file
%   a_jsonDeploymentRefFile : json sensor reference file
%
% OUTPUT PARAMETERS :
%
% EXAMPLES :
%
% SEE ALSO :
% AUTHOR : Jean-Philippe Rannou (Capgemini) (jean.philippe.rannou@partenaire-exterieur.ifremer.fr)
% ------------------------------------------------------------------------------
% RELEASES :
%   02/22/2019 - RNU - creation
% ------------------------------------------------------------------------------
function gl_convert_json_files(a_deploymentDirName, a_deploymentName, ...
   a_jsonDeploymentRefFile, a_jsonSensorRefFile)

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% check that the main json file is in version 1.3
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

deployJsonFile = [a_deploymentDirName '/json/' a_deploymentName '.json'];
if ~(exist(deployJsonFile, 'file') == 2)
   fprintf('ERROR: expected json deployment file not found (%s) => deployment ignored\n', ...
      deployJsonFile);
   return
end

% read the json deployment file
try
   deployJsonData = gl_load_json(deployJsonFile);
catch MException
   fprintf('ERROR: error format in json file (%s)\n', ...
      deployJsonFile);
   fprintf('%s\n', ...
      MException.message);
   return
end

okGo = 0;
if (isfield(deployJsonData, 'EGO_format_version'))
   if (strcmp(deployJsonData.EGO_format_version, '1.3'))
      okGo = 1;
   end
end
if (~okGo)
   fprintf('ERROR: json file not in expected 1.3 version (%s)\n', ...
      deployJsonFile);
   return
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% make a copy of the json directory
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

deployJsonDir = [a_deploymentDirName '/json/'];
deployJsonDirOld = [a_deploymentDirName '/json_1.3/'];
copyfile(deployJsonDir, deployJsonDirOld);

fprintf('Converting json deployment file: %s\n', ...
   deployJsonFile);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% list of global attributes
deployGlobAttList = {
   'platform_code', ...
   'wmo_platform_code', ...
   'comment', ...
   'title', ...
   'summary', ...
   'abstract', ...
   'keywords', ...
   'area', ...
   'institution', ...
   'institution_references', ...
   'sdn_edmo_code', ...
   'authors', ...
   'data_assembly_center', ...
   'principal_investigator', ...
   'principal_investigator_email', ...
   'project_name', ...
   'observatory', ...
   'deployment_code', ...
   'deployment_label', ...
   'doi', ...
   'update_interval', ...
   'citation', ...
   'references' ...
   };

inputFields = fields(deployJsonData.global_attributes);
globAttStruct = [];
for idGa = 1:length(deployGlobAttList)
   outputField = deployGlobAttList{idGa};
   globAttStruct.(outputField) = '';
   idF = find(cellfun(@(x) strncmp(outputField, x, length(outputField)), inputFields) == 1);
   if (~isempty(idF))
      if (length(idF) > 1)
         idF = find(cellfun(@(x) strcmp(outputField, x), inputFields) == 1);
      end
      if (~isempty(deployJsonData.global_attributes.(inputFields{idF})))
         globAttStruct.(outputField) = deployJsonData.global_attributes.(inputFields{idF});
      end
   elseif (strcmp(outputField, 'authors'))
      globAttStruct.(outputField) = deployJsonData.global_attributes.author;
   elseif (strcmp(outputField, 'citation'))
      globAttStruct.(outputField) = 'These data were collected and made freely available by the EGO project and the national programs that contribute to it.';
   elseif (strcmp(outputField, 'references'))
      globAttStruct.(outputField) = 'http://www.ego-network.org/';
   end
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% list of glider characteristics
deployGliderCharactList = {
   'PLATFORM_FAMILY', ...
   'PLATFORM_TYPE', ...
   'PLATFORM_MAKER', ...
   'GLIDER_SERIAL_NO', ...
   'GLIDER_OWNER', ...
   'OPERATING_INSTITUTION', ...
   'WMO_INST_TYPE', ...
   'POSITIONING_SYSTEM', ...
   'TRANS_SYSTEM', ...
   'TRANS_SYSTEM_ID', ...
   'TRANS_FREQUENCY', ...
   'BATTERY_TYPE', ...
   'BATTERY_PACKS', ...
   'SPECIAL_FEATURES', ...
   'FIRMWARE_VERSION_NAVIGATION', ...
   'FIRMWARE_VERSION_SCIENCE', ...
   'LANDSTATION_SOFTWARE_VERSION', ...
   'GLIDER_MANUAL_VERSION', ...
   'ANOMALY', ...
   'CUSTOMIZATION', ...
   'DAC_FORMAT_ID' ...
   };

inputFields = fields(deployJsonData.glider_characteristics);
gliderCharStruct = [];
for idGc = 1:length(deployGliderCharactList)
   outputField = deployGliderCharactList{idGc};
   gliderCharStruct.(outputField) = '';
   idF = find(cellfun(@(x) strncmp(outputField, x, length(outputField)), inputFields) == 1);
   if (~isempty(idF))
      if (length(idF) > 1)
         idF = find(cellfun(@(x) strcmp(outputField, x), inputFields) == 1);
      end
      if (~isempty(deployJsonData.glider_characteristics.(inputFields{idF})))
         gliderCharStruct.(outputField) = deployJsonData.glider_characteristics.(inputFields{idF});
      end
   end
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% list of glider deployment items
deployGliderDeployList = {
   'DEPLOYMENT_START_DATE', ...
   'DEPLOYMENT_START_LATITUDE', ...
   'DEPLOYMENT_START_LONGITUDE', ...
   'DEPLOYMENT_START_QC', ...
   'DEPLOYMENT_PLATFORM', ...
   'DEPLOYMENT_CRUISE_ID', ...
   'DEPLOYMENT_REFERENCE_STATION_ID', ...
   'DEPLOYMENT_END_DATE', ...
   'DEPLOYMENT_END_LATITUDE', ...
   'DEPLOYMENT_END_LONGITUDE', ...
   'DEPLOYMENT_END_QC', ...
   'DEPLOYMENT_END_STATUS', ...
   'DEPLOYMENT_OPERATOR' ...
   };

inputFields = fields(deployJsonData.glider_deployment);
gliderDeplStruct = [];
for idGd = 1:length(deployGliderDeployList)
   outputField = deployGliderDeployList{idGd};
   gliderDeplStruct.(outputField) = '';
   idF = find(cellfun(@(x) strncmp(outputField, x, length(outputField)), inputFields) == 1);
   if (~isempty(idF))
      if (length(idF) > 1)
         idF = find(cellfun(@(x) strcmp(outputField, x), inputFields) == 1);
      end
      if (~isempty(deployJsonData.glider_deployment.(inputFields{idF})))
         gliderDeplStruct.(outputField) = deployJsonData.glider_deployment.(inputFields{idF});
      end
   end
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% coordinate variables
coorVarData = [];
inputData = deployJsonData.coordinate_variables;
for idCv = 1:length(inputData)
   coorData = inputData(idCv);
   if (ismember(coorData.ego_variable_name, [{'TIME'}, {'LATITUDE'}, {'LONGITUDE'}]))
      coorVarData = [coorVarData coorData];
   end
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% glider sensors
glSensorData = deployJsonData.glider_sensor;

glSensorFileData = [];
for idGs = 1:length(glSensorData)
   glSensor = glSensorData(idGs);
   sensorFileName = glSensor.sensor_file_name;
   
   sensorJsonFile = [a_deploymentDirName '/json_1.3/' sensorFileName];
   if ~(exist(sensorJsonFile, 'file') == 2)
      fprintf('ERROR: expected json sensor file not found (%s) => deployment ignored\n', ...
         sensorJsonFile);
      return
   end
   
   fprintf('Converting json sensor file: %s\n', ...
      sensorJsonFile);

   % read JSON sensor contents
   % open the file
   fIdIn = fopen(sensorJsonFile, 'r');
   if (fIdIn == -1)
      fprintf('ERROR: While openning file : %s\n', sensorJsonFile);
      return
   end

   % read the data
   sensorJsonData = [];
   while (1)
      line = fgetl(fIdIn);
      if (line == -1)
         break
      end
      sensorJsonData{end+1} = line;
   end
   fclose(fIdIn);

   dataStruct = [];
   dataStruct.file = sensorFileName;
   dataStruct.data = sensorJsonData;
   glSensorFileData = [glSensorFileData dataStruct];
end


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% CREATE JSON DEPLOYMENT FILE
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% read reference JSON deployment contents
% open the file
fIdIn = fopen(a_jsonDeploymentRefFile, 'r');
if (fIdIn == -1)
   fprintf('ERROR: While openning file : %s\n', a_jsonDeploymentRefFile);
   return
end

% read the data
jsonDeployRef = [];
while (1)
   line = fgetl(fIdIn);
   if (line == -1)
      break
   end
   jsonDeployRef{end+1} = line;
end
fclose(fIdIn);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% list of numeric items
numericItemList = {
   'DEPLOYMENT_START_LATITUDE', ...
   'DEPLOYMENT_START_LONGITUDE', ...
   'DEPLOYMENT_START_QC', ...
   'DEPLOYMENT_END_LATITUDE', ...
   'DEPLOYMENT_END_LONGITUDE', ...
   'DEPLOYMENT_END_QC' ...
   };

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% list of multi-dim items
multiDimItemList = {
   'POSITIONING_SYSTEM', ...
   'TRANS_SYSTEM', ...
   'TRANS_SYSTEM_ID', ...
   'TRANS_FREQUENCY' ...
   };

% convert deployment file
jsonDeploy = [];
currentStruct = [];
for idL = 1:length(jsonDeployRef)
   line = jsonDeployRef{idL};
   
   if (any(strfind(line, 'global_attributes')))
      currentStruct = globAttStruct;
   elseif (any(strfind(line, 'glider_characteristics')))
      currentStruct = gliderCharStruct;
   elseif (any(strfind(line, 'glider_deployment')))
      currentStruct = gliderDeplStruct;
   elseif (any(strfind(line, 'coordinate_variables')))
      currentStruct = [];
   elseif (any(strfind(line, 'glider_sensor')))
      currentStruct = [];
   end
   
   if (any(strfind(line, '<') & strfind(line, '>')))
      posStart = strfind(line, '<');
      posEnd = strfind(line, '>');
      pattern = line(posStart:posEnd);
      patternName = line(posStart+1:posEnd-1);
      
      patternValue = '';
      if (~isempty(currentStruct))
         if (ismember(patternName, multiDimItemList))
            dataValue = currentStruct.(patternName);
            if (ischar(dataValue) && (size(dataValue, 1) > 1))
               dataValue = cellstr(dataValue)';
            end
            if (iscellstr(dataValue))
               dataValueList = sprintf('"%s", ', dataValue{:});
               patternValue = sprintf('[%s]', dataValueList(1:end-2));
            else
               patternValue = sprintf('"%s"', dataValue);
            end
         elseif (strcmp(patternName, 'authors'))
            dataValue = currentStruct.(patternName);

            patternValue = [patternValue '[\n'];
            for idA = 1:length(dataValue)
               dataV = dataValue(idA);
               patternValue = [patternValue '            {\n'];
               patternValue = [patternValue sprintf('                "first_name": "%s",\n', dataV.first_name)];
               patternValue = [patternValue sprintf('                "last_name": "%s",\n', dataV.last_name)];
               patternValue = [patternValue sprintf('                "email": "%s",\n', dataV.email)];
               patternValue = [patternValue sprintf('                "orcid": "%s",\n', dataV.orcid)];
               patternValue = [patternValue sprintf('                "affiliations": "%s"\n', dataV.affiliations)];
               if (idA == length(dataValue))
                  patternValue = [patternValue '            }\n'];
               else
                  patternValue = [patternValue '            },\n'];
               end
            end
            patternValue = [patternValue '        ]'];
         else
            if (ischar(currentStruct.(patternName)) || iscell(currentStruct.(patternName)))
               patternValue = currentStruct.(patternName);
            else
               patternValue = num2str(currentStruct.(patternName));
            end
            if (isempty(patternValue))
               if (ismember(patternName, numericItemList))
                  patternValue = 'null';
               end
            end
         end
      elseif (strcmp(patternName, 'coordinate_variables'))
         for idCv = 1:length(coorVarData)
            coorVar = coorVarData(idCv);
            patternValue = [patternValue '        {\n'];
            patternValue = [patternValue sprintf('            "glider_variable_name": "%s",\n', coorVar.glider_variable_name)];
            patternValue = [patternValue sprintf('            "ego_variable_name": "%s"\n', coorVar.ego_variable_name)];
            patternValue = [patternValue '        }'];
            if (idCv < length(coorVarData))
               patternValue = [patternValue ',\n'];
            end
         end
      elseif (strcmp(patternName, 'glider_sensor'))
         for idGs = 1:length(glSensorData)
            glSensor = glSensorData(idGs);
            patternValue = [patternValue '        {\n'];
            patternValue = [patternValue sprintf('            "sensor_file_name": "%s"\n', glSensor.sensor_file_name)];
            patternValue = [patternValue '        }'];
            if (idGs < length(glSensorData))
               patternValue = [patternValue ',\n'];
            end
         end
      end
      line = regexprep(line, pattern, patternValue);
   end
   
   jsonDeploy{end+1} = sprintf('%s', line);
end

% create output directory
outputDirName = [a_deploymentDirName '/json/'];
if (exist(outputDirName, 'dir') == 7)
   %    fprintf('ERROR: directory %s already exists => deployment ignored\n', ...
   %       outputDirName);
   %    return
else
   mkdir(outputDirName);
end

% create deployment file
ouputDeployJsonFile = [outputDirName '/' a_deploymentName '.json'];
fIdOut = fopen(ouputDeployJsonFile, 'wt');
if (fIdOut == -1)
   fprintf('ERROR: While creating file : %s\n', ouputDeployJsonFile);
   return
end

fprintf(fIdOut, '%s\n', jsonDeploy{:});

fclose(fIdOut);


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% CREATE JSON SENSOR FILES
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% convert sensor files
for idGs = 1:length(glSensorFileData)
   glSensor = glSensorFileData(idGs);
   glSensorData = glSensor.data;

   % modify file version
   idF = cellfun(@(x) strfind(glSensorData, x), {'EGO_format_version'}, 'UniformOutput', 0);
   idF = find(~cellfun(@isempty, idF{:}));
   if (~isempty(idF))
      glSensorData{idF} = regexprep(glSensorData{idF}, '1.3', '1.4');
   end

   % create sensor file
   ouputSensorJsonFile = [outputDirName '/' glSensor.file];
   fIdOut = fopen(ouputSensorJsonFile, 'wt');
   if (fIdOut == -1)
      fprintf('ERROR: While creating file : %s\n', ouputSensorJsonFile);
      return
   end
   
   fprintf(fIdOut, '%s\n', glSensorData{:});
   
   fclose(fIdOut);
end

return
