% ------------------------------------------------------------------------------
% Convert JSON deployment and sensor files from EGO 1.2 to EGO 1.3.
% The default behaviour is :
%    - to process all the deployments (the directories) stored in the
%      DATA_DIRECTORY directory
% this behaviour can be modified by input arguments.
%
% SYNTAX :
%   gl_convert_json_files_from_1_2_to_1_3(varargin)
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
%   02/22/2019 - RNU - creation
% ------------------------------------------------------------------------------
function gl_convert_json_files_from_1_2_to_1_3(varargin)

% top directory of the deployment directories
% DATA_DIRECTORY = 'C:\Users\jprannou\_DATA\GLIDER\FORMAT_1.4/';
DATA_DIRECTORY = 'C:\Users\jprannou\_DATA\GLIDER\slocum/';
DATA_DIRECTORY = 'C:\Users\jprannou\_DATA\GLIDER\seaglider/';
DATA_DIRECTORY = 'C:\Users\jprannou\_DATA\GLIDER\seaexplorer/';

% directory to store log files
DIR_LOG_FILE = 'C:\Users\jprannou\_RNU\Glider\work\log\';

% reference file for JSON deployment file
JSON_DEPLOYMENT_REF_FILE = 'C:\Users\jprannou\_RNU\Glider\soft\util\json\deployment_ref_1_3.json';

% reference file for JSON sensor file
JSON_SENSOR_REF_FILE = 'C:\Users\jprannou\_RNU\Glider\soft\util\json\sensor_ref_1_3.json';

% default values initialization
gl_init_default_values;


% create and start log file recording
logFile = [DIR_LOG_FILE '/' 'gl_convert_json_files_from_1_2_to_1_3_' datestr(now, 'yyyymmddTHHMMSS') '.log'];
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
% check that the main json file is in version 1.2
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
FIST_TIME = 1;
if (FIST_TIME)
   deployJsonFile = [a_deploymentDirName '/json/' a_deploymentName '.json'];
else
   deployJsonFile = [a_deploymentDirName '/json_1.2/' a_deploymentName '.json'];
end
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
if (~isfield(deployJsonData, 'EGO_format_version'))
   okGo = 1;
end
if (~okGo)
   fprintf('ERROR: json file not in expected 1.2 version (%s)\n', ...
      deployJsonFile);
   return
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% make a copy of the json directory
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

if (FIST_TIME)
   deployJsonDir = [a_deploymentDirName '/json/'];
   deployJsonDirOld = [a_deploymentDirName '/json_1.2/'];
   copyfile(deployJsonDir, deployJsonDirOld);
end

fprintf('Converting json deployment file: %s\n', ...
   deployJsonFile);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% READ INPUT JSON FILES
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

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
   'update_interval' ...
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
   end
end

if (strcmp(strtrim(globAttStruct.update_interval), '6 hours'))
   globAttStruct.update_interval = 'daily';
end
if (strcmp(strtrim(globAttStruct.data_assembly_center), 'FMI'))
   globAttStruct.data_assembly_center = '';
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

if (strcmp(strtrim(gliderCharStruct.PLATFORM_FAMILY), 'coastal glider'))
   gliderCharStruct.PLATFORM_FAMILY = 'COASTAL_GLIDER';
end
if (strcmp(strtrim(gliderCharStruct.PLATFORM_FAMILY), 'Open ocean glider'))
   gliderCharStruct.PLATFORM_FAMILY = 'OPEN_OCEAN_GLIDER';
end
if (strcmp(strtrim(gliderCharStruct.PLATFORM_FAMILY), 'open ocean glider'))
   gliderCharStruct.PLATFORM_FAMILY = 'OPEN_OCEAN_GLIDER';
end
if (strcmp(strtrim(gliderCharStruct.PLATFORM_TYPE), 'Slocum') && strcmp(strtrim(gliderCharStruct.PLATFORM_FAMILY), 'G1'))
   gliderCharStruct.PLATFORM_FAMILY = '';
   gliderCharStruct.PLATFORM_TYPE = 'SLOCUM_SG1';
end
if (strcmp(strtrim(gliderCharStruct.PLATFORM_TYPE), 'Slocum') && strcmp(strtrim(gliderCharStruct.PLATFORM_FAMILY), 'G2'))
   gliderCharStruct.PLATFORM_FAMILY = '';
   gliderCharStruct.PLATFORM_TYPE = 'SLOCUM_SG2';
end
if (strcmp(strtrim(gliderCharStruct.PLATFORM_TYPE), 'Deep Slocum'))
   gliderCharStruct.PLATFORM_TYPE = 'SLOCUM_SG1';
end
if (strcmp(strtrim(gliderCharStruct.PLATFORM_TYPE), 'Slocum'))
   gliderCharStruct.PLATFORM_TYPE = 'SLOCUM_SG1';
end
if (strcmp(strtrim(gliderCharStruct.PLATFORM_TYPE), 'Slocum SG1'))
   gliderCharStruct.PLATFORM_TYPE = 'SLOCUM_SG1';
end
if (strcmp(strtrim(gliderCharStruct.PLATFORM_TYPE), 'Slocum  G1 deep'))
   gliderCharStruct.PLATFORM_TYPE = 'SLOCUM_SG1';
end
if (strcmp(strtrim(gliderCharStruct.PLATFORM_TYPE), 'Slocum  G1 shallow'))
   gliderCharStruct.PLATFORM_TYPE = 'SLOCUM_SG1';
end
if (strcmp(strtrim(gliderCharStruct.PLATFORM_TYPE), 'Slocum G1 1000m'))
   gliderCharStruct.PLATFORM_TYPE = 'SLOCUM_SG1';
end
if (strcmp(strtrim(gliderCharStruct.PLATFORM_TYPE), 'Slocum G1 200m'))
   gliderCharStruct.PLATFORM_TYPE = 'SLOCUM_SG1';
end
if (strcmp(strtrim(gliderCharStruct.PLATFORM_FAMILY), 'Slocum 200m'))
   gliderCharStruct.PLATFORM_FAMILY = 'COASTAL_GLIDER';
end
if (strcmp(strtrim(gliderCharStruct.PLATFORM_TYPE), 'Slocum G2 1000m'))
   gliderCharStruct.PLATFORM_TYPE = 'SLOCUM_SG2';
end
if (strcmp(strtrim(gliderCharStruct.PLATFORM_TYPE), 'Slocum G2 deep with SUNA'))
   gliderCharStruct.PLATFORM_TYPE = 'SLOCUM_SG2';
end
if (strcmp(strtrim(gliderCharStruct.PLATFORM_TYPE), 'Seaglider'))
   gliderCharStruct.PLATFORM_TYPE = 'SEAGLIDER';
end
if (strcmp(strtrim(gliderCharStruct.PLATFORM_MAKER), 'iRobot') && strcmp(strtrim(gliderCharStruct.PLATFORM_TYPE), 'SEAGLIDER'))
   gliderCharStruct.PLATFORM_MAKER = 'KONGSBERG';
end
if (strcmp(strtrim(gliderCharStruct.PLATFORM_MAKER), 'Kongsberg'))
   gliderCharStruct.PLATFORM_MAKER = 'KONGSBERG';
end
if (strcmp(strtrim(gliderCharStruct.PLATFORM_MAKER), 'University of Washington'))
   gliderCharStruct.PLATFORM_MAKER = 'UNIVERSITY_OF_WASHINGTON';
end
if (strcmp(strtrim(gliderCharStruct.PLATFORM_MAKER), 'Teledyne Webb research'))
   gliderCharStruct.PLATFORM_MAKER = 'WRC';
end
if (strcmp(strtrim(gliderCharStruct.PLATFORM_MAKER), 'Webb Research Corporation'))
   gliderCharStruct.PLATFORM_MAKER = 'WRC';
end
if (strcmp(strtrim(gliderCharStruct.PLATFORM_MAKER), 'Teledyne'))
   gliderCharStruct.PLATFORM_MAKER = 'WRC';
end
if (strcmp(strtrim(gliderCharStruct.PLATFORM_MAKER), 'Webb Research Cooperation'))
   gliderCharStruct.PLATFORM_MAKER = 'WRC';
end
if (strcmp(strtrim(gliderCharStruct.PLATFORM_MAKER), 'Teledyne Webb Research'))
   gliderCharStruct.PLATFORM_MAKER = 'WRC';
end
for idP = 1:length(gliderCharStruct.POSITIONING_SYSTEM)
   if (strcmp(gliderCharStruct.POSITIONING_SYSTEM{idP}, 'Iridium'))
      gliderCharStruct.POSITIONING_SYSTEM{idP} = 'IRIDIUM';
   end
end
if (size(gliderCharStruct.TRANS_SYSTEM, 1) == 1)
   if (strcmp(gliderCharStruct.TRANS_SYSTEM, 'Iridium'))
      gliderCharStruct.TRANS_SYSTEM = 'IRIDIUM';
   end
   if (strcmp(gliderCharStruct.TRANS_SYSTEM, 'ARGOS'))
      gliderCharStruct.TRANS_SYSTEM = '';
   end
   if (strcmp(gliderCharStruct.TRANS_SYSTEM, 'Argos'))
      gliderCharStruct.TRANS_SYSTEM = '';
   end
   if (strcmp(gliderCharStruct.TRANS_SYSTEM, 'Triniumxx'))
      gliderCharStruct.TRANS_SYSTEM = '';
   end
else
   for idT = 1:length(gliderCharStruct.TRANS_SYSTEM)
      if (strcmp(gliderCharStruct.TRANS_SYSTEM{idT}, 'Iridium'))
         gliderCharStruct.TRANS_SYSTEM{idT} = 'IRIDIUM';
      end
      if (strcmp(gliderCharStruct.TRANS_SYSTEM{idT}, 'Argos'))
         gliderCharStruct.TRANS_SYSTEM{idT} = '';
      end
      if (strcmp(gliderCharStruct.TRANS_SYSTEM{idT}, 'ARGOS'))
         gliderCharStruct.TRANS_SYSTEM{idT} = '';
      end
      if (strcmp(gliderCharStruct.TRANS_SYSTEM{idT}, 'Triniumxx'))
         gliderCharStruct.TRANS_SYSTEM{idT} = '';
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
      gliderVarName = coorData.glider_variable_name;
      idF = strfind(gliderVarName, '.');
      coorData.glider_variable_name = gliderVarName(idF(end)+1:end);
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
   
   sensorJsonFile = [a_deploymentDirName '/json_1.2/' sensorFileName];
   if ~(exist(sensorJsonFile, 'file') == 2)
      fprintf('ERROR: expected json sensor file not found (%s) => deployment ignored\n', ...
         sensorJsonFile);
      return
   end
   
   fprintf('Converting json sensor file: %s\n', ...
      sensorJsonFile);
   
   % read the json sensor file
   try
      sensorJsonData = gl_load_json(sensorJsonFile);
   catch MException
      fprintf('ERROR: error format in json file (%s)\n', ...
         sensorJsonFile);
      fprintf('%s\n', ...
         MException.message);
      return
   end
   
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
            
            firstName = '';
            lastName = '';
            email = '';
            affiliation = '';
            if (any(strfind(dataValue, '@')))
               email = dataValue;
               idF = strfind(dataValue, '@');
               if (length(idF) == 1)
                  part1 = dataValue(1:idF-1);
                  part2 = dataValue(idF+1:end);
                  if (any(strfind(part1, '.')))
                     idF = strfind(part1, '.');
                     if (length(idF) == 1)
                        firstName = part1(1:idF-1);
                        lastName = upper(part1(idF+1:end));
                     end
                  end
                  if (any(strfind(part2, '.')))
                     idF = strfind(part2, '.');
                     if (length(idF) == 1)
                        affiliation = part2(1:idF-1);
                     end
                  end
               end
            else
               dataValue = strtrim(dataValue);
               dataValue = regexprep(dataValue, '  ', ' ');
               idF = strfind(dataValue, ' ');
               if (length(idF) == 1)
                  firstName = dataValue(1:idF(1)-1);
                  lastName = upper(dataValue(idF(1)+1:end));
               end
            end
            patternValue = [patternValue '[\n'];
            patternValue = [patternValue '            {\n'];
            patternValue = [patternValue sprintf('                "first_name": "%s",\n', firstName)];
            patternValue = [patternValue sprintf('                "last_name": "%s",\n', lastName)];
            patternValue = [patternValue sprintf('                "email": "%s",\n', email)];
            patternValue = [patternValue '                "orcid": "",\n'];
            patternValue = [patternValue sprintf('                "affiliations": "%s"\n', affiliation)];
            patternValue = [patternValue '            }\n'];
            patternValue = [patternValue '        ]'];
            
            fprintf('\nCheck conversion from ''author'' to ''authors''\n');
            fprintf('INPUT ''author'': %s\n', dataValue);
            fprintf('OUTPUT ''authors'':\n');
            fprintf('first_name: "%s"\n', firstName);
            fprintf('last_name: "%s"\n', lastName);
            fprintf('email: "%s"\n\n', email);
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

% read reference JSON sensor contents
% open the file
fIdIn = fopen(a_jsonSensorRefFile, 'r');
if (fIdIn == -1)
   fprintf('ERROR: While openning file : %s\n', a_jsonSensorRefFile);
   return
end

% read the data
jsonSensorRef = [];
while (1)
   line = fgetl(fIdIn);
   if (line == -1)
      break
   end
   jsonSensorRef{end+1} = line;
end
fclose(fIdIn);

% convert sensor files
for idGs = 1:length(glSensorFileData)
   glSensor = glSensorFileData(idGs);
   glSensorData = glSensor.data;
   paramList = glSensorData.parametersList;
   
   paramDataTab = [];
   for idP = 1:length(paramList)
      paramInfo = paramList(idP);
      
      paramData = [];
      if (strcmp(paramInfo.ego_variable_name, 'PRES'))
         paramData.PARAMETER_SENSOR = 'CTD_PRES';
         paramData.PARAMETER_UNITS = 'decibar';
      elseif (strcmp(paramInfo.ego_variable_name, 'TEMP'))
         paramData.PARAMETER_SENSOR = 'CTD_TEMP';
         paramData.PARAMETER_UNITS = 'degree_Celsius';
      elseif (strcmp(paramInfo.ego_variable_name, 'CNDC'))
         paramData.PARAMETER_SENSOR = 'CTD_CNDC';
         paramData.PARAMETER_UNITS = 'mhos/m';
      elseif (strcmp(paramInfo.ego_variable_name, 'PSAL'))
         paramData.PARAMETER_SENSOR = 'CTD_CNDC';
         paramData.PARAMETER_UNITS = 'psu';
      elseif (strcmp(paramInfo.ego_variable_name, 'CHLA'))
         paramData.PARAMETER_SENSOR = 'FLUOROMETER_CHLA';
         paramData.PARAMETER_UNITS = 'mg/m3';
      elseif (strcmp(paramInfo.ego_variable_name, 'CDOM'))
         paramData.PARAMETER_SENSOR = 'FLUOROMETER_CDOM';
         paramData.PARAMETER_UNITS = 'ppb';
      elseif (strcmp(paramInfo.ego_variable_name, 'BBP700'))
         paramData.PARAMETER_SENSOR = 'BACKSCATTERINGMETER_BBP700';
         paramData.PARAMETER_UNITS = 'm-1';
      elseif (strcmp(paramInfo.ego_variable_name, 'BBP715'))
         paramData.PARAMETER_SENSOR = 'BACKSCATTERINGMETER_BBP715';
         paramData.PARAMETER_UNITS = 'm-1';
      elseif (strcmp(paramInfo.ego_variable_name, 'BBP532'))
         paramData.PARAMETER_SENSOR = 'BACKSCATTERINGMETER_BBP532';
         paramData.PARAMETER_UNITS = 'm-1';
      elseif (strcmp(paramInfo.ego_variable_name, 'BBP660'))
         paramData.PARAMETER_SENSOR = 'BACKSCATTERINGMETER_BBP660';
         paramData.PARAMETER_UNITS = 'm-1';
      elseif (strcmp(paramInfo.ego_variable_name, 'BBP470'))
         paramData.PARAMETER_SENSOR = 'BACKSCATTERINGMETER_BBP470';
         paramData.PARAMETER_UNITS = 'm-1';
      elseif (strcmp(paramInfo.ego_variable_name, 'BBP412'))
         paramData.PARAMETER_SENSOR = 'BACKSCATTERINGMETER_BBP412';
         paramData.PARAMETER_UNITS = 'm-1';
      elseif (strcmp(paramInfo.ego_variable_name, 'BBP880'))
         paramData.PARAMETER_SENSOR = 'BACKSCATTERINGMETER_BBP880';
         paramData.PARAMETER_UNITS = 'm-1';
      elseif (strcmp(paramInfo.ego_variable_name, 'MOLAR_DOXY'))
         paramData.PARAMETER_SENSOR = 'OPTODE_DOXY';
         paramData.PARAMETER_UNITS = 'umol/L';
      elseif (strcmp(paramInfo.ego_variable_name, 'TEMP_DOXY'))
         paramData.PARAMETER_SENSOR = 'OPTODE_DOXY';
         paramData.PARAMETER_UNITS = 'degree_Celsius';
      elseif (strcmp(paramInfo.ego_variable_name, 'C1PHASE_DOXY'))
         paramData.PARAMETER_SENSOR = 'OPTODE_DOXY';
         paramData.PARAMETER_UNITS = 'degree';
      elseif (strcmp(paramInfo.ego_variable_name, 'C2PHASE_DOXY'))
         paramData.PARAMETER_SENSOR = 'OPTODE_DOXY';
         paramData.PARAMETER_UNITS = 'degree';
      elseif (strcmp(paramInfo.ego_variable_name, 'TPHASE_DOXY'))
         paramData.PARAMETER_SENSOR = 'OPTODE_DOXY';
         paramData.PARAMETER_UNITS = 'degree';
      elseif (strcmp(paramInfo.ego_variable_name, 'BPHASE_DOXY'))
         paramData.PARAMETER_SENSOR = 'OPTODE_DOXY';
         paramData.PARAMETER_UNITS = 'degree';
      elseif (strcmp(paramInfo.ego_variable_name, 'RPHASE_DOXY'))
         paramData.PARAMETER_SENSOR = 'OPTODE_DOXY';
         paramData.PARAMETER_UNITS = 'degree';
      elseif (strcmp(paramInfo.ego_variable_name, 'DPHASE_DOXY'))
         paramData.PARAMETER_SENSOR = 'OPTODE_DOXY';
         paramData.PARAMETER_UNITS = 'degree';
      elseif (strcmp(paramInfo.ego_variable_name, 'MOLAR_NITRATE'))
         paramData.PARAMETER_SENSOR = 'SPECTROPHOTOMETER_NITRATE';
         paramData.PARAMETER_UNITS = 'umol/L';
      elseif (strcmp(paramInfo.ego_variable_name, 'TURBIDITY'))
         paramData.PARAMETER_SENSOR = 'BACKSCATTERINGMETER_TURBIDITY';
         paramData.PARAMETER_UNITS = 'ntu';
      elseif (strcmp(paramInfo.ego_variable_name, 'FLUORESCENCE_PE'))
         paramData.PARAMETER_SENSOR = 'UNKNOWN';
         paramData.PARAMETER_UNITS = 'ppb';
      else

         fprintf('\nERROR: not managed ego_variable_name: ''%s''\n\n', paramInfo.ego_variable_name);
         
         paramData.PARAMETER_SENSOR = '';
         paramData.PARAMETER_UNITS = '';
      end
      paramData.PARAMETER = paramInfo.ego_variable_name;
      paramData.PARAMETER_DATA_MODE = 'R';
      paramData.PARAMETER_ACCURACY = '';
      paramData.PARAMETER_RESOLUTION = '';
      paramData.ego_variable_name = paramInfo.ego_variable_name;
      gliderVarName = paramInfo.glider_variable_name;
      idF = strfind(gliderVarName, '.');
      if (~isempty(idF))
         gliderVarName = gliderVarName(idF(end)+1:end);
      end
      paramData.glider_variable_name = gliderVarName;
      paramData.comment = '';
      paramData.cell_methods = paramInfo.cell_methods;
      paramData.reference_scale = paramInfo.reference_scale;
      paramData.derivation_equation = paramInfo.derivation_equation;
      paramData.derivation_coefficient = paramInfo.derivation_coefficient;
      paramData.derivation_comment = paramInfo.derivation_comment;
      paramData.derivation_date = paramInfo.derivation_date;
      paramData.processing_id = '';
      
      paramDataTab = [paramDataTab paramData];
   end
   
   jsonSensor = [];
   for idL = 1:length(jsonSensorRef)
      line = jsonSensorRef{idL};
      
      if (any(strfind(line, '<') & strfind(line, '>')))
         posStart = strfind(line, '<');
         posEnd = strfind(line, '>');
         pattern = line(posStart:posEnd);
         patternName = line(posStart+1:posEnd-1);
         
         patternValue = '';

         info = -1;
         if (ismember('PRES', {paramDataTab.PARAMETER}) && ...
               ismember('TEMP', {paramDataTab.PARAMETER}) && ...
               ismember('PSAL', {paramDataTab.PARAMETER}) && ...
               ismember('CNDC', {paramDataTab.PARAMETER}) && ...
               (length({paramDataTab.PARAMETER}) == 4))
            info = 1;
            nbSensor = 3;
         elseif (ismember('PRES', {paramDataTab.PARAMETER}) && ...
               ismember('TEMP', {paramDataTab.PARAMETER}) && ...
               ismember('PSAL', {paramDataTab.PARAMETER}) && ...
               (length({paramDataTab.PARAMETER}) == 3))
            info = 2;
            nbSensor = 3;
         elseif (ismember('CHLA', {paramDataTab.PARAMETER}) && ...
               ismember('CDOM', {paramDataTab.PARAMETER}) && ...
               ismember('BBP700', {paramDataTab.PARAMETER}) && ...
               (length({paramDataTab.PARAMETER}) == 3))
            info = 3;
            nbSensor = 3;
         elseif (ismember('MOLAR_DOXY', {paramDataTab.PARAMETER}) && ...
               ismember('TEMP_DOXY', {paramDataTab.PARAMETER}) && ...
               ismember('C1PHASE_DOXY', {paramDataTab.PARAMETER}) && ...
               ismember('C2PHASE_DOXY', {paramDataTab.PARAMETER}) && ...
               ismember('TPHASE_DOXY', {paramDataTab.PARAMETER}) && ...
               (length({paramDataTab.PARAMETER}) == 5))
            info = 4;
            nbSensor = 1;
         elseif (ismember('MOLAR_DOXY', {paramDataTab.PARAMETER}) && ...
               (length({paramDataTab.PARAMETER}) == 1))
            info = 5;
            nbSensor = 1;
         elseif (ismember('CHLA', {paramDataTab.PARAMETER}) && ...
               (length({paramDataTab.PARAMETER}) == 1))
            info = 6;
            nbSensor = 1;
         elseif (ismember('CDOM', {paramDataTab.PARAMETER}) && ...
               (length({paramDataTab.PARAMETER}) == 1))
            info = 7;
            nbSensor = 1;
         elseif (ismember('MOLAR_NITRATE', {paramDataTab.PARAMETER}) && ...
               (length({paramDataTab.PARAMETER}) == 1))
            info = 8;
            nbSensor = 1;
         elseif (ismember('BBP532', {paramDataTab.PARAMETER}) && ...
               ismember('CDOM', {paramDataTab.PARAMETER}) && ...
               ismember('BBP660', {paramDataTab.PARAMETER}) && ...
               (length({paramDataTab.PARAMETER}) == 3))
            info = 9;
            nbSensor = 3;
         elseif (ismember('CHLA', {paramDataTab.PARAMETER}) && ...
               ismember('BBP470', {paramDataTab.PARAMETER}) && ...
               ismember('BBP412', {paramDataTab.PARAMETER}) && ...
               (length({paramDataTab.PARAMETER}) == 3))
            info = 10;
            nbSensor = 3;
         elseif (ismember('CHLA', {paramDataTab.PARAMETER}) && ...
               ismember('TURBIDITY', {paramDataTab.PARAMETER}) && ...
               (length({paramDataTab.PARAMETER}) == 2))
            info = 11;
            nbSensor = 2;
         elseif (ismember('MOLAR_DOXY', {paramDataTab.PARAMETER}) && ...
               ismember('BPHASE_DOXY', {paramDataTab.PARAMETER}) && ...
               ismember('RPHASE_DOXY', {paramDataTab.PARAMETER}) && ...
               (length({paramDataTab.PARAMETER}) == 3))
            info = 12;
            nbSensor = 1;
         elseif (ismember('BBP532', {paramDataTab.PARAMETER}) && ...
               ismember('CDOM', {paramDataTab.PARAMETER}) && ...
               ismember('BBP880', {paramDataTab.PARAMETER}) && ...
               (length({paramDataTab.PARAMETER}) == 3))
            info = 13;
            nbSensor = 3;
         elseif (ismember('MOLAR_DOXY', {paramDataTab.PARAMETER}) && ...
               ismember('TEMP_DOXY', {paramDataTab.PARAMETER}) && ...
               ismember('BPHASE_DOXY', {paramDataTab.PARAMETER}) && ...
               ismember('RPHASE_DOXY', {paramDataTab.PARAMETER}) && ...
               (length({paramDataTab.PARAMETER}) == 4))
            info = 14;
            nbSensor = 1;
         elseif (ismember('MOLAR_DOXY', {paramDataTab.PARAMETER}) && ...
               ismember('BPHASE_DOXY', {paramDataTab.PARAMETER}) && ...
               (length({paramDataTab.PARAMETER}) == 2))
            info = 15;
            nbSensor = 1;
         elseif (ismember('CHLA', {paramDataTab.PARAMETER}) && ...
               ismember('CDOM', {paramDataTab.PARAMETER}) && ...
               ismember('BBP532', {paramDataTab.PARAMETER}) && ...
               (length({paramDataTab.PARAMETER}) == 3))
            info = 16;
            nbSensor = 3;
         elseif (ismember('CHLA', {paramDataTab.PARAMETER}) && ...
               ismember('BBP532', {paramDataTab.PARAMETER}) && ...
               ismember('BBP470', {paramDataTab.PARAMETER}) && ...
               (length({paramDataTab.PARAMETER}) == 3))
            info = 17;
            nbSensor = 3;
         elseif (ismember('CDOM', {paramDataTab.PARAMETER}) && ...
               ismember('BBP660', {paramDataTab.PARAMETER}) && ...
               ismember('BBP880', {paramDataTab.PARAMETER}) && ...
               (length({paramDataTab.PARAMETER}) == 3))
            info = 18;
            nbSensor = 3;
         elseif (ismember('MOLAR_DOXY', {paramDataTab.PARAMETER}) && ...
               ismember('TEMP_DOXY', {paramDataTab.PARAMETER}) && ...
               ismember('BPHASE_DOXY', {paramDataTab.PARAMETER}) && ...
               ismember('DPHASE_DOXY', {paramDataTab.PARAMETER}) && ...
               ismember('RPHASE_DOXY', {paramDataTab.PARAMETER}) && ...
               (length({paramDataTab.PARAMETER}) == 5))
            info = 19;
            nbSensor = 1;
         elseif (ismember('MOLAR_DOXY', {paramDataTab.PARAMETER}) && ...
               ismember('TEMP_DOXY', {paramDataTab.PARAMETER}) && ...
               (length({paramDataTab.PARAMETER}) == 2))
            info = 20;
            nbSensor = 1;
         elseif (ismember('CHLA', {paramDataTab.PARAMETER}) && ...
               ismember('BBP700', {paramDataTab.PARAMETER}) && ...
               (length({paramDataTab.PARAMETER}) == 2))
            info = 21;
            nbSensor = 2;
         elseif (ismember('BBP715', {paramDataTab.PARAMETER}) && ...
               (length({paramDataTab.PARAMETER}) == 1))
            info = 22;
            nbSensor = 3;
         elseif (ismember('CHLA', {paramDataTab.PARAMETER}) && ...
               ismember('CDOM', {paramDataTab.PARAMETER}) && ...
               (length({paramDataTab.PARAMETER}) == 2))
            info = 23;
            nbSensor = 2;
         elseif (ismember('MOLAR_DOXY', {paramDataTab.PARAMETER}) && ...
               ismember('TEMP_DOXY', {paramDataTab.PARAMETER}) && ...
               ismember('TPHASE_DOXY', {paramDataTab.PARAMETER}) && ...
               (length({paramDataTab.PARAMETER}) == 3))
            info = 24;
            nbSensor = 1;
         elseif (ismember('BBP470', {paramDataTab.PARAMETER}) && ...
               ismember('BBP700', {paramDataTab.PARAMETER}) && ...
               ismember('CHLA', {paramDataTab.PARAMETER}) && ...
               (length({paramDataTab.PARAMETER}) == 3))
            info = 25;
            nbSensor = 3;
         elseif (ismember('BBP880', {paramDataTab.PARAMETER}) && ...
               ismember('BBP715', {paramDataTab.PARAMETER}) && ...
               ismember('FLUORESCENCE_PE', {paramDataTab.PARAMETER}) && ...
               (length({paramDataTab.PARAMETER}) == 3))
            info = 26;
            nbSensor = 3;
         elseif (ismember('BBP532', {paramDataTab.PARAMETER}) && ...
               ismember('CDOM', {paramDataTab.PARAMETER}) && ...
               ismember('FLUORESCENCE_PE', {paramDataTab.PARAMETER}) && ...
               (length({paramDataTab.PARAMETER}) == 3))
            info = 27;
            nbSensor = 3;
         elseif (ismember('BBP470', {paramDataTab.PARAMETER}) && ...
               ismember('BBP532', {paramDataTab.PARAMETER}) && ...
               ismember('BBP660', {paramDataTab.PARAMETER}) && ...
               (length({paramDataTab.PARAMETER}) == 3))
            info = 28;
            nbSensor = 3;
         elseif (ismember('CHLA', {paramDataTab.PARAMETER}) && ...
               ismember('BBP715', {paramDataTab.PARAMETER}) && ...
               ismember('CDOM', {paramDataTab.PARAMETER}) && ...
               (length({paramDataTab.PARAMETER}) == 3))
            info = 29;
            nbSensor = 3;
         else

            fprintf('\nERROR: not managed PARAMETER list: ''%s''\n\n', paramDataTab.PARAMETER);

            nbSensor = length({paramDataTab.PARAMETER_SENSOR});
         end

         switch (patternName)
            case 'SENSOR'
               if (info == 1)
                  dataList = unique({paramDataTab.PARAMETER_SENSOR}, 'stable');
               elseif (info == 2)
                  dataList = unique({paramDataTab.PARAMETER_SENSOR}, 'stable');
               elseif (info == 3)
                  dataList = [{'FLUOROMETER_CHLA'} {'FLUOROMETER_CDOM'} {'BACKSCATTERINGMETER_BBP700'}];
               elseif (info == 4)
                  dataList = {'OPTODE_DOXY'};
               elseif (info == 5)
                  dataList = {'OPTODE_DOXY'};
               elseif (info == 6)
                  dataList = {'FLUOROMETER_CHLA'};
               elseif (info == 7)
                  dataList = {'FLUOROMETER_CDOM'};
               elseif (info == 8)
                  dataList = {'SPECTROPHOTOMETER_NITRATE'};
               elseif (info == 9)
                  dataList = [{'BACKSCATTERINGMETER_BBP532'} {'FLUOROMETER_CDOM'} {'BACKSCATTERINGMETER_BBP660'}];
               elseif (info == 10)
                  dataList = [{'FLUOROMETER_CHLA'} {'BACKSCATTERINGMETER_BBP470'} {'BACKSCATTERINGMETER_BBP412'}];
               elseif (info == 11)
                  dataList = [{'FLUOROMETER_CHLA'} {'BACKSCATTERINGMETER_TURBIDITY'}];
               elseif (info == 12)
                  dataList = {'OPTODE_DOXY'};
               elseif (info == 13)
                  dataList = [{'BACKSCATTERINGMETER_BBP532'} {'FLUOROMETER_CDOM'} {'BACKSCATTERINGMETER_BBP880'}];
               elseif (info == 14)
                  dataList = {'OPTODE_DOXY'};
               elseif (info == 15)
                  dataList = {'OPTODE_DOXY'};
               elseif (info == 16)
                  dataList = [{'FLUOROMETER_CHLA'} {'FLUOROMETER_CDOM'} {'BACKSCATTERINGMETER_BBP532'}];
               elseif (info == 17)
                  dataList = [{'FLUOROMETER_CHLA'} {'BACKSCATTERINGMETER_BBP532'} {'BACKSCATTERINGMETER_BBP470'}];
               elseif (info == 18)
                  dataList = [{'FLUOROMETER_CDOM'} {'BACKSCATTERINGMETER_BBP660'} {'BACKSCATTERINGMETER_BBP880'}];
               elseif (info == 19)
                  dataList = {'OPTODE_DOXY'};
               elseif (info == 20)
                  dataList = {'OPTODE_DOXY'};
               elseif (info == 21)
                  dataList = [{'FLUOROMETER_CHLA'} {'BACKSCATTERINGMETER_BBP700'}];
               elseif (info == 22)
                  dataList = {'BACKSCATTERINGMETER_BBP715'};
               elseif (info == 23)
                  dataList = [{'FLUOROMETER_CHLA'} {'FLUOROMETER_CDOM'}];
               elseif (info == 24)
                  dataList = {'OPTODE_DOXY'};
               elseif (info == 25)
                  dataList = [{'BACKSCATTERINGMETER_BBP470'} {'BACKSCATTERINGMETER_BBP700'} {'FLUOROMETER_CHLA'}];
               elseif (info == 26)
                  dataList = [{'BACKSCATTERINGMETER_BBP880'} {'BACKSCATTERINGMETER_BBP715'} {'UNKNOWN'}];
               elseif (info == 27)
                  dataList = [{'BACKSCATTERINGMETER_BBP532'} {'FLUOROMETER_CDOM'} {'UNKNOWN'}];
               elseif (info == 28)
                  dataList = [{'BACKSCATTERINGMETER_BBP470'} {'BACKSCATTERINGMETER_BBP532'} {'BACKSCATTERINGMETER_BBP660'}];
               elseif (info == 29)
                  dataList = [{'FLUOROMETER_CHLA'} {'BACKSCATTERINGMETER_BBP715'} {'FLUOROMETER_CDOM'}];
               else

                  fprintf('\nERROR: not managed PARAMETER_SENSOR: ''%s''\n\n', paramDataTab.PARAMETER_SENSOR);

                  paramDataTab.PARAMETER_SENSOR
                  dataList = cell(1, nbSensor);
               end
               dataValueList = sprintf('"%s", ', dataList{:});
               patternValue = sprintf('[%s]', dataValueList(1:end-2));

            case {'SENSOR_MAKER'}
               if (strcmp(strtrim(glSensorData.SENSOR_MAKER), 'SeaBird Electronics'))
                  dataList = repmat({'SBE'}, 1, nbSensor);
               elseif (strcmp(strtrim(glSensorData.SENSOR_MAKER), 'Seabird'))
                  dataList = repmat({'SBE'}, 1, nbSensor);
               elseif (strcmp(strtrim(glSensorData.SENSOR_MAKER), 'Sea-Bird'))
                  dataList = repmat({'SBE'}, 1, nbSensor);
               elseif (strcmp(strtrim(glSensorData.SENSOR_MAKER), 'Sea-Bird Scientific'))
                  dataList = repmat({'SBE'}, 1, nbSensor);
               elseif (strcmp(strtrim(glSensorData.SENSOR_MAKER), 'SEABIRD'))
                  dataList = repmat({'SBE'}, 1, nbSensor);
               elseif (strcmp(strtrim(glSensorData.SENSOR_MAKER), 'SBE'))
                  dataList = repmat({'SBE'}, 1, nbSensor);
               elseif (strcmp(strtrim(glSensorData.SENSOR_MAKER), 'Wetlabs'))
                  dataList = repmat({'WETLABS'}, 1, nbSensor);
               elseif (strcmp(strtrim(glSensorData.SENSOR_MAKER), 'WET Labs'))
                  dataList = repmat({'WETLABS'}, 1, nbSensor);
               elseif (strcmp(strtrim(glSensorData.SENSOR_MAKER), 'WetLabs'))
                  dataList = repmat({'WETLABS'}, 1, nbSensor);
               elseif (strcmp(strtrim(glSensorData.SENSOR_MAKER), 'Aanderaa'))
                  dataList = repmat({'AANDERAA'}, 1, nbSensor);
               elseif (strcmp(strtrim(glSensorData.SENSOR_MAKER), 'AANDERAA'))
                  dataList = repmat({'AANDERAA'}, 1, nbSensor);
               elseif (strcmp(strtrim(glSensorData.SENSOR_MAKER), 'Aanderaa Data Instruments AS'))
                  dataList = repmat({'AANDERAA'}, 1, nbSensor);
               elseif (strcmp(strtrim(glSensorData.SENSOR_MAKER), 'Aandera'))
                  dataList = repmat({'AANDERAA'}, 1, nbSensor);
               elseif (strcmp(strtrim(glSensorData.SENSOR_MAKER), 'Satlantic Inc.'))
                  dataList = repmat({'SATLANTIC'}, 1, nbSensor);
               elseif (strcmp(strtrim(glSensorData.SENSOR_MAKER), 'Teledyne Webb research') && strcmp(strtrim(glSensorData.SENSOR_MODEL), 'Oxy 4831'))
                  dataList = repmat({'AANDERAA'}, 1, nbSensor);
               elseif (isempty(glSensorData.SENSOR_MAKER) && strcmp(strtrim(glSensorData.SENSOR_MODEL), 'CTD'))
                  dataList = repmat({'SBE'}, 1, nbSensor);
               elseif (isempty(glSensorData.SENSOR_MAKER) && strcmp(strtrim(glSensorData.SENSOR_MODEL), 'Oxy'))
                  dataList = repmat({'AANDERAA'}, 1, nbSensor);
               elseif (isempty(strtrim(glSensorData.SENSOR_NAME)) && ...
                     isempty(strtrim(glSensorData.SENSOR_MAKER)) && ...
                     isempty(strtrim(glSensorData.SENSOR_MODEL)) && ...
                     (ismember('PRES', {paramDataTab.PARAMETER}) && ...
                     ismember('TEMP', {paramDataTab.PARAMETER}) && ...
                     ismember('PSAL', {paramDataTab.PARAMETER}) && ...
                     ismember('CNDC', {paramDataTab.PARAMETER}) && ...
                     (length({paramDataTab.PARAMETER}) == 4)))
                  dataList = repmat({'SBE'}, 1, nbSensor);
               elseif (strcmp(strtrim(glSensorData.SENSOR_NAME), 'CTD') && ...
                     isempty(strtrim(glSensorData.SENSOR_MAKER)) && ...
                     isempty(strtrim(glSensorData.SENSOR_MODEL)) && ...
                     (ismember('PRES', {paramDataTab.PARAMETER}) && ...
                     ismember('TEMP', {paramDataTab.PARAMETER}) && ...
                     ismember('PSAL', {paramDataTab.PARAMETER}) && ...
                     ismember('CNDC', {paramDataTab.PARAMETER}) && ...
                     (length({paramDataTab.PARAMETER}) == 4)))
                  dataList = repmat({'SBE'}, 1, nbSensor);
               elseif (strcmp(strtrim(glSensorData.SENSOR_MAKER), 'AANDERAA') && strcmp(strtrim(glSensorData.SENSOR_NAME), 'DOXY'))
                  dataList = repmat({'AANDERAA'}, 1, nbSensor);
               elseif (isempty(glSensorData.SENSOR_MAKER) && strcmp(strtrim(glSensorData.SENSOR_NAME), 'SUNA'))
                  dataList = repmat({'SATLANTIC'}, 1, nbSensor);
               elseif (strcmp(strtrim(glSensorData.SENSOR_MAKER), 'SUNA'))
                  dataList = repmat({'SATLANTIC'}, 1, nbSensor);
               else

                  fprintf('\nERROR: not managed SENSOR_MAKER: ''%s''\n\n', glSensorData.SENSOR_MAKER);
                  
                  glSensorData.SENSOR_MAKER
                  dataList = cell(1, nbSensor);
               end
               dataValueList = sprintf('"%s", ', dataList{:});
               patternValue = sprintf('[%s]', dataValueList(1:end-2));

            case {'SENSOR_MODEL'}
               if (strcmp(strtrim(glSensorData.SENSOR_MODEL), 'CTD 41cp'))
                  dataList = repmat({'SBE41CP'}, 1, nbSensor);
               elseif (strcmp(strtrim(glSensorData.SENSOR_MODEL), '41 CP'))
                  dataList = repmat({'SBE41CP'}, 1, nbSensor);
               elseif (strcmp(strtrim(glSensorData.SENSOR_MODEL), 'SBE 41'))
                  dataList = repmat({'SBE41'}, 1, nbSensor);
               elseif (strcmp(strtrim(glSensorData.SENSOR_MODEL), 'flbbcdslc'))
                  dataList = [{'ECO_FLBBCD'} {'ECO_FLBBCD'} {'ECO_FLBBCD'}];
               elseif (strcmp(strtrim(glSensorData.SENSOR_MODEL), 'Oxy 4831F'))
                  dataList = repmat({'AANDERAA_OPTODE_4831F'}, 1, nbSensor);
               elseif (strcmp(strtrim(glSensorData.SENSOR_MODEL), 'Oxy 5013'))
                  dataList = repmat({'AANDERAA_OPTODE_5013'}, 1, nbSensor);
               elseif (strcmp(strtrim(glSensorData.SENSOR_MODEL), 'Oxy 5014'))
                  dataList = repmat({'AANDERAA_OPTODE_5014'}, 1, nbSensor);
               elseif (strcmp(strtrim(glSensorData.SENSOR_MODEL), 'Oxygen Optode 4330/4330F'))
                  dataList = repmat({'AANDERAA_OPTODE_4330F'}, 1, nbSensor);
               elseif (strcmp(strtrim(glSensorData.SENSOR_MODEL), 'Optode 4330'))
                  dataList = repmat({'AANDERAA_OPTODE_4330'}, 1, nbSensor);
               elseif (strcmp(strtrim(glSensorData.SENSOR_MODEL), 'bb2flslk V1'))
                  dataList = repmat({'ECO_FLBB2'}, 1, nbSensor);
               elseif (strcmp(strtrim(glSensorData.SENSOR_MODEL), 'bb2flslk V4'))
                  dataList = repmat({'ECO_FLBB2'}, 1, nbSensor);
               elseif (strcmp(strtrim(glSensorData.SENSOR_MODEL), 'bb2flslk V2'))
                  dataList = repmat({'ECO_FLBB2'}, 1, nbSensor);
               elseif (strcmp(strtrim(glSensorData.SENSOR_MODEL), 'bb2flslk V3'))
                  dataList = repmat({'ECO_FLBB2'}, 1, nbSensor);
               elseif (strcmp(strtrim(glSensorData.SENSOR_MODEL), 'bb2flslk V5'))
                  dataList = repmat({'ECO_FLBB2'}, 1, nbSensor);
               elseif (strcmp(strtrim(glSensorData.SENSOR_MODEL), 'ECO Puck bb2flsv2'))
                  dataList = repmat({'ECO_FLBB2'}, 1, nbSensor);
               elseif (strcmp(strtrim(glSensorData.SENSOR_MODEL), 'BB2FL-VMT'))
                  dataList = repmat({'ECO_FLBB2'}, 1, nbSensor);
               elseif (strcmp(strtrim(glSensorData.SENSOR_MODEL), 'bbfl2slk V1'))
                  dataList = repmat({'ECO_FLBBCD'}, 1, nbSensor);
               elseif (strcmp(strtrim(glSensorData.SENSOR_MODEL), 'BBL2SLC'))
                  dataList = repmat({'ECO_FLBBCD'}, 1, nbSensor);
               elseif (strcmp(strtrim(glSensorData.SENSOR_MODEL), 'flbbcd'))
                  dataList = repmat({'ECO_FLBBCD'}, 1, nbSensor);
               elseif (strcmp(strtrim(glSensorData.SENSOR_MODEL), 'SUNA'))
                  dataList = repmat({'SUNA_V2'}, 1, nbSensor);
               elseif (strcmp(strtrim(glSensorData.SENSOR_MODEL), 'CTD') && strcmp(strtrim(glSensorData.SENSOR_MAKER), 'SeaBird Electronics'))
                  dataList = repmat({'SBE'}, 1, nbSensor);
               elseif (strcmp(strtrim(glSensorData.SENSOR_MODEL), 'Oxy 4831'))
                  dataList = repmat({'AANDERAA_OPTODE_4831'}, 1, nbSensor);
               elseif (strcmp(strtrim(glSensorData.SENSOR_MODEL), 'bb2flslk V6'))
                  dataList = repmat({'ECO_FLBB2'}, 1, nbSensor);
               elseif (strcmp(strtrim(glSensorData.SENSOR_MODEL), 'flntu'))
                  dataList = repmat({'ECO_FLNTU'}, 1, nbSensor);
               elseif (strcmp(strtrim(glSensorData.SENSOR_MODEL), 'ECO FLNT PUCK'))
                  dataList = repmat({'ECO_FLNTU'}, 1, nbSensor);
               elseif (strcmp(strtrim(glSensorData.SENSOR_MODEL), 'FLNTUS'))
                  dataList = repmat({'ECO_FLNTU'}, 1, nbSensor);
               elseif (strcmp(strtrim(glSensorData.SENSOR_MODEL), 'flntuslc'))
                  dataList = repmat({'ECO_FLNTU'}, 1, nbSensor);
               elseif (strcmp(strtrim(glSensorData.SENSOR_MODEL), 'Eco Flntu'))
                  dataList = repmat({'ECO_FLNTU'}, 1, nbSensor);
               elseif (isempty(glSensorData.SENSOR_MODEL) && strcmp(strtrim(glSensorData.SENSOR_NAME), 'Aanderaa Oxy'))
                  dataList = repmat({'AANDERAA_OPTODE'}, 1, nbSensor);
               elseif (strcmp(strtrim(glSensorData.SENSOR_NAME), 'Aanderaa Oxy'))
                  dataList = repmat({'AANDERAA_OPTODE'}, 1, nbSensor);
               elseif (isempty(glSensorData.SENSOR_MAKER) && strcmp(strtrim(glSensorData.SENSOR_MODEL), 'CTD'))
                  dataList = repmat({'SBE'}, 1, nbSensor);
               elseif (isempty(glSensorData.SENSOR_MAKER) && strcmp(strtrim(glSensorData.SENSOR_MODEL), 'Oxy'))
                  dataList = repmat({'AANDERAA_OPTODE'}, 1, nbSensor);
               elseif (strcmp(strtrim(glSensorData.SENSOR_MODEL), 'CTD 41cp_V2'))
                  dataList = repmat({'SBE41CP_V2'}, 1, nbSensor);
               elseif (strcmp(strtrim(glSensorData.SENSOR_MODEL), 'ECO FLNTU PUCK'))
                  dataList = repmat({'ECO_FLNTU'}, 1, nbSensor);
               elseif (strcmp(strtrim(glSensorData.SENSOR_MODEL), 'ECO FLBBCD PUCK'))
                  dataList = repmat({'ECO_FLBBCD'}, 1, nbSensor);
               elseif (strcmp(strtrim(glSensorData.SENSOR_MAKER), 'Seabird') && strcmp(strtrim(glSensorData.SENSOR_MODEL), 'pumped CTD'))
                  dataList = repmat({'SBE'}, 1, nbSensor);
               elseif (strcmp(strtrim(glSensorData.SENSOR_MODEL), 'bbfl2slc'))
                  dataList = [{'ECO_FLBBCD'} {'ECO_FLBBCD'} {'ECO_FLBBCD'}];
               elseif (isempty(strtrim(glSensorData.SENSOR_NAME)) && ...
                     isempty(strtrim(glSensorData.SENSOR_MAKER)) && ...
                     isempty(strtrim(glSensorData.SENSOR_MODEL)) && ...
                     (ismember('PRES', {paramDataTab.PARAMETER}) && ...
                     ismember('TEMP', {paramDataTab.PARAMETER}) && ...
                     ismember('PSAL', {paramDataTab.PARAMETER}) && ...
                     ismember('CNDC', {paramDataTab.PARAMETER}) && ...
                     (length({paramDataTab.PARAMETER}) == 4)))
                  dataList = repmat({'SBE'}, 1, nbSensor);
               elseif (isempty(glSensorData.SENSOR_MODEL) && strcmp(strtrim(glSensorData.SENSOR_MAKER), 'SeaBird Electronics') && strcmp(strtrim(glSensorData.SENSOR_NAME), 'SeaBird Electronics'))
                  dataList = repmat({'SBE'}, 1, nbSensor);
               elseif (strcmp(strtrim(glSensorData.SENSOR_NAME), 'CTD') && ...
                     isempty(strtrim(glSensorData.SENSOR_MAKER)) && ...
                     isempty(strtrim(glSensorData.SENSOR_MODEL)) && ...
                     (ismember('PRES', {paramDataTab.PARAMETER}) && ...
                     ismember('TEMP', {paramDataTab.PARAMETER}) && ...
                     ismember('PSAL', {paramDataTab.PARAMETER}) && ...
                     ismember('CNDC', {paramDataTab.PARAMETER}) && ...
                     (length({paramDataTab.PARAMETER}) == 4)))
                  dataList = repmat({'SBE'}, 1, nbSensor);
               elseif (strcmp(strtrim(glSensorData.SENSOR_MAKER), 'AANDERAA') && strcmp(strtrim(glSensorData.SENSOR_NAME), 'DOXY'))
                  dataList = repmat({'AANDERAA_OPTODE'}, 1, nbSensor);
               elseif (isempty(glSensorData.SENSOR_MODEL) && strcmp(strtrim(glSensorData.SENSOR_MAKER), 'SEABIRD') && strcmp(strtrim(glSensorData.SENSOR_NAME), 'CTD'))
                  dataList = repmat({'SBE'}, 1, nbSensor);
               elseif (strcmp(strtrim(glSensorData.SENSOR_MAKER), 'Seabird') && strcmp(strtrim(glSensorData.SENSOR_MODEL), 'Slocum CTD'))
                  dataList = repmat({'SBE'}, 1, nbSensor);
               elseif (strcmp(strtrim(glSensorData.SENSOR_MODEL), 'GPCTD unpumped'))
                  dataList = repmat({'SBE_GPCTD'}, 1, nbSensor);
               elseif (strcmp(strtrim(glSensorData.SENSOR_MODEL), 'GPCTD'))
                  dataList = repmat({'SBE_GPCTD'}, 1, nbSensor);
               elseif (strcmp(strtrim(glSensorData.SENSOR_MODEL), 'SBE'))
                  dataList = repmat({'SBE'}, 1, nbSensor);
               elseif (strcmp(strtrim(glSensorData.SENSOR_MODEL), 'Non-Pumped CTD'))
                  dataList = repmat({'SBE'}, 1, nbSensor);
               elseif (strcmp(strtrim(glSensorData.SENSOR_MODEL), 'unpumped CTD') && strcmp(strtrim(glSensorData.SENSOR_NAME), 'CTD41CP'))
                  dataList = repmat({'SBE41CP'}, 1, nbSensor);
               elseif (strcmp(strtrim(glSensorData.SENSOR_MODEL), 'SBE 37'))
                  dataList = repmat({'SBE37'}, 1, nbSensor);
               elseif (strcmp(strtrim(glSensorData.SENSOR_MODEL), 'SUNA nitrate sensor'))
                  dataList = repmat({'SUNA_V2'}, 1, nbSensor);
               elseif (strcmp(strtrim(glSensorData.SENSOR_MODEL), '3830'))
                  dataList = repmat({'AANDERAA_OPTODE_3830'}, 1, nbSensor);
               elseif (strcmp(strtrim(glSensorData.SENSOR_MODEL), 'OPTODE 3835'))
                  dataList = repmat({'AANDERAA_OPTODE_3835'}, 1, nbSensor);
               elseif (strcmp(strtrim(glSensorData.SENSOR_MODEL), 'Optode 4831'))
                  dataList = repmat({'AANDERAA_OPTODE_4831'}, 1, nbSensor);
               elseif (strcmp(strtrim(glSensorData.SENSOR_MODEL), 'G-1451'))
                  dataList = repmat({'SBE'}, 1, nbSensor);
               elseif (strcmp(strtrim(glSensorData.SENSOR_MODEL), 'ECO Triplet FLBBCD-SLK'))
                  dataList = repmat({'ECO_FLBBCD'}, 1, nbSensor);
               elseif (strcmp(strtrim(glSensorData.SENSOR_MODEL), 'Scientific GPCTD'))
                  dataList = repmat({'SBE_GPCTD'}, 1, nbSensor);
               elseif (strcmp(strtrim(glSensorData.SENSOR_MODEL), 'CTDAPL'))
                  dataList = repmat({'SBE'}, 1, nbSensor);
               elseif (strcmp(strtrim(glSensorData.SENSOR_MODEL), 'SX glider'))
                  dataList = repmat({'SBE'}, 1, nbSensor);
               elseif (strcmp(strtrim(glSensorData.SENSOR_MODEL), 'ECO_FLBBCD'))
                  dataList = repmat({'ECO_FLBBCD'}, 1, nbSensor);
               elseif (strcmp(strtrim(glSensorData.SENSOR_MODEL), 'ECO BB3SLO PUCK'))
                  dataList = repmat({'ECO_BB3'}, 1, nbSensor);
               else

                  fprintf('\nERROR: not managed SENSOR_MODEL: ''%s''\n\n', glSensorData.SENSOR_MODEL);

                  glSensorData.SENSOR_MODEL
                  dataList = cell(1, nbSensor);
               end
               dataValueList = sprintf('"%s", ', dataList{:});
               patternValue = sprintf('[%s]', dataValueList(1:end-2));

            case {'SENSOR_ORIENTATION'}
               dataList = cell(1, nbSensor);
               dataValueList = sprintf('"%s", ', dataList{:});
               patternValue = sprintf('[%s]', dataValueList(1:end-2));
            case 'SENSOR_SERIAL_NO'
               if (isempty(glSensorData.SENSOR_SERIAL_NO))
                  glSensorData.SENSOR_SERIAL_NO = '99999';
               end
               dataValueList = repmat(sprintf('"%s", ', glSensorData.SENSOR_SERIAL_NO), 1, nbSensor);
               patternValue = sprintf('[%s]', dataValueList(1:end-2));
            case 'SENSOR_MOUNT'
               dataValueList = repmat('"MOUNTED_ON_GLIDER", ', 1, nbSensor);
               patternValue = sprintf('[%s]', dataValueList(1:end-2));
               
            case 'PARAMETER'
               dataList = {paramDataTab.PARAMETER};
               dataValueList = sprintf('"%s", ', dataList{:});
               patternValue = sprintf('[%s]', dataValueList(1:end-2));
            case 'PARAMETER_SENSOR'
               dataList = {paramDataTab.PARAMETER_SENSOR};
               dataValueList = sprintf('"%s", ', dataList{:});
               patternValue = sprintf('[%s]', dataValueList(1:end-2));
            case 'PARAMETER_DATA_MODE'
               dataList = {paramDataTab.PARAMETER_DATA_MODE};
               dataValueList = sprintf('"%s", ', dataList{:});
               patternValue = sprintf('[%s]', dataValueList(1:end-2));
            case 'PARAMETER_UNITS'
               dataList = {paramDataTab.PARAMETER_UNITS};
               dataValueList = sprintf('"%s", ', dataList{:});
               patternValue = sprintf('[%s]', dataValueList(1:end-2));
            case 'PARAMETER_ACCURACY'
               dataList = {paramDataTab.PARAMETER_ACCURACY};
               dataValueList = sprintf('"%s", ', dataList{:});
               patternValue = sprintf('[%s]', dataValueList(1:end-2));
            case 'PARAMETER_RESOLUTION'
               dataList = {paramDataTab.PARAMETER_RESOLUTION};
               dataValueList = sprintf('"%s", ', dataList{:});
               patternValue = sprintf('[%s]', dataValueList(1:end-2));
               
            case 'parametersList'
               for idP = 1:length(paramDataTab)
                  paramData = paramDataTab(idP);

                  if (length(paramData.derivation_date) == 8)
                     paramData.derivation_date = [paramData.derivation_date '000000'];
                  end

                  patternValue = [patternValue '        {\n'];
                  patternValue = [patternValue sprintf('            "ego_variable_name"     : "%s",\n', paramData.ego_variable_name)];
                  patternValue = [patternValue sprintf('            "glider_variable_name"  : "%s",\n', paramData.glider_variable_name)];
                  patternValue = [patternValue sprintf('            "comment"               : "%s",\n', paramData.comment)];
                  patternValue = [patternValue sprintf('            "cell_methods"          : "%s",\n', paramData.cell_methods)];
                  patternValue = [patternValue sprintf('            "reference_scale"       : "%s",\n', paramData.reference_scale)];
                  patternValue = [patternValue '\n'];
                  patternValue = [patternValue sprintf('            "derivation_equation"   : "%s",\n', paramData.derivation_equation)];
                  patternValue = [patternValue sprintf('            "derivation_coefficient": "%s",\n', paramData.derivation_coefficient)];
                  patternValue = [patternValue sprintf('            "derivation_comment"    : "%s",\n', paramData.derivation_comment)];
                  patternValue = [patternValue sprintf('            "derivation_date"       : "%s",\n', paramData.derivation_date)];
                  patternValue = [patternValue '\n'];
                  patternValue = [patternValue sprintf('            "processing_id": "%s"\n', paramData.processing_id)];
                  patternValue = [patternValue '        }'];
                  if (idP < length(paramDataTab))
                     patternValue = [patternValue ',\n'];
                  end
               end
         end
         
         line = regexprep(line, pattern, patternValue);
      end
      
      jsonSensor{end+1} = sprintf('%s', line);
   end
   
   % create sensor file
   ouputSensorJsonFile = [outputDirName '/' glSensor.file];
   fIdOut = fopen(ouputSensorJsonFile, 'wt');
   if (fIdOut == -1)
      fprintf('ERROR: While creating file : %s\n', ouputSensorJsonFile);
      return
   end
   
   fprintf(fIdOut, '%s\n', jsonSensor{:});
   
   fclose(fIdOut);
end

return
