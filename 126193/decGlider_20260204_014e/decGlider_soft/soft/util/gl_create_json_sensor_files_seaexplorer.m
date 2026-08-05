% ------------------------------------------------------------------------------
% Generate json sensor files from available data (and existing sensor files).
%
% SYNTAX :
%   gl_create_json_sensor_files_seaexplorer or
%   gl_create_json_sensor_files_seaexplorer('data', 'crate_mooset00_38')
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
%   12/04/2023 - RNU - creation
% ------------------------------------------------------------------------------
function gl_create_json_sensor_files_seaexplorer(varargin)

% top directory of the input deployment directories
INPUT_DATA_DIRECTORY = 'C:\Users\jprannou\_DATA\GLIDER\seaexplorer\';

% top directory of the output
OUTPUT_DATA_DIRECTORY = 'C:\Users\jprannou\_DATA\GLIDER\out\';

% directory to store the log file
DIR_LOG_FILE = 'C:\Users\jprannou\_RNU\Glider\work\log\';

% directory to store the CSV file
DIR_CSV_FILE = 'C:\Users\jprannou\_RNU\Glider\work\csv\';

% available data mat file
AVAILABLE_DATA_FILE_NAME = 'C:\Users\jprannou\_RNU\Glider\work\seaexplorer_available_data.mat';

% default values initialization
gl_init_default_values;


% check configuration information
if ~(exist(INPUT_DATA_DIRECTORY, 'dir') == 7)
   fprintf('ERROR: ''DATA_DIRECTORY'' directory not found: %s\n', DATA_DIRECTORY);
   return
end

if ~(exist(OUTPUT_DATA_DIRECTORY, 'dir') == 7)
   mkdir(OUTPUT_DATA_DIRECTORY);
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
            if (exist([INPUT_DATA_DIRECTORY '/' varargin{id+1}], 'dir'))
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
logFile = [DIR_LOG_FILE '/' 'gl_create_json_sensor_files_seaexplorer_' deploymentDir '_' datestr(now, 'yyyymmddTHHMMSS') '.log'];
diary(logFile);
tic;

% create the CSV output file
csvFile = [DIR_CSV_FILE '/' 'gl_create_json_sensor_files_seaexplorer_' deploymentDir '_' datestr(now, 'yyyymmddTHHMMSS') '.csv'];
fidOut = fopen(csvFile, 'wt');
if (fidOut == -1)
   return
end
header = 'MSG TYPE;DEPLOYMENT;SENSOR LABEL;SENSOR/PARAMETER;SENSOR NAME;ACTION;PREV VALUE;NEW VALUE';
fprintf(fidOut, '%s\n', header);

% generate deployment sensor files
if (isempty(deploymentDir))
   % check all the deployments of the DATA_DIRECTORY directory
   dirInfo = dir(INPUT_DATA_DIRECTORY);
   for dirNum = 1:length(dirInfo)
      if ~(strcmp(dirInfo(dirNum).name, '.') || strcmp(dirInfo(dirNum).name, '..'))
         dirName = dirInfo(dirNum).name;

         gl_create_json_sensor_file(INPUT_DATA_DIRECTORY, OUTPUT_DATA_DIRECTORY, dirName, AVAILABLE_DATA_FILE_NAME, fidOut);
      end
   end
else
   % generate sensor files for this deployment
   gl_create_json_sensor_file(INPUT_DATA_DIRECTORY, OUTPUT_DATA_DIRECTORY, deploymentDir, AVAILABLE_DATA_FILE_NAME, fidOut);
end

fclose(fidOut);

ellapsedTime = toc;
fprintf('done (Elapsed time is %.1f seconds)\n', ellapsedTime);
fprintf('See updates in file %s\n', csvFile);

diary off;

return

% ------------------------------------------------------------------------------
% Generate json sensor files for a given deployment (and existing sensor files).
%
% SYNTAX :
% gl_create_json_sensor_file(a_deployInputDirName, a_deployOutputDirName, ...
%   a_deploymentDirName, a_availableDataFile, a_csvFid)
%
% INPUT PARAMETERS :
%   a_deployInputDirName  : top directory of input deployments directory
%   a_deployOutputDirName : top directory of output deployments directory
%   a_deploymentDirName   : directory of the deployment
%   a_availableDataFile   : list of already checked available data
%   a_csvFid              : output CSv file Id
%
% OUTPUT PARAMETERS :
%
% EXAMPLES :
%
% SEE ALSO :
% AUTHOR : Jean-Philippe Rannou (Capgemini) (jean.philippe.rannou@partenaire-exterieur.ifremer.fr)
% ------------------------------------------------------------------------------
% RELEASES :
%   12/04/2023 - RNU - creation
% ------------------------------------------------------------------------------
function gl_create_json_sensor_file(a_deployInputDirName, a_deployOutputDirName, ...
   a_deploymentDirName, a_availableDataFile, a_csvFid)

fprintf('Processing deployment: %s\n', a_deploymentDirName);

% retrieve glider parameter names and associated available data

availDataStruct = [];
found = 0;
if (exist(a_availableDataFile, 'file') == 2)
   info = load(a_availableDataFile);
   availDataStruct= info.availDataStruct;
   clear info
   idF = find(strcmp(a_deploymentDirName, {availDataStruct.deployName}));
   if (~isempty(idF))
      availableParam = availDataStruct(idF).gliderParam;
      availableData = availDataStruct(idF).gliderData;
      found = 1;
   end
end

if (~found)
   [availableParam, availableData] = gl_get_available_data_seaexplorer(a_deployInputDirName, a_deploymentDirName);
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

availableParam(availableData == 0) = [];
if (isempty(availableParam))
   fprintf('WARNING: no available parameters in deployment: %s\n', a_deploymentDirName);
   return
end

% read the json deployment file
deployJsonDirName = [a_deployInputDirName '\' a_deploymentDirName '\json\'];
deployJsonFilePathName = [deployJsonDirName a_deploymentDirName '.json'];
deployJsonData = gl_load_json(deployJsonFilePathName);
if (isempty(deployJsonData))
   return
end

% json sensor file output directory
outputDirName = [a_deployOutputDirName '\' a_deploymentDirName '\json\'];
if ~(exist(outputDirName, 'dir') == 7)
   mkdir(outputDirName);
end

sensorFileNameList = [];

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% CTD

sensorStructOld = [];
gliderVarNameList = [];
egoVarNameListCtd = [];
if (any(strcmp('GPCTD_PRESSURE', availableParam)) && ...
      any(strcmp('GPCTD_TEMPERATURE', availableParam)) && ...
      any(strcmp('GPCTD_CONDUCTIVITY', availableParam)))

   gliderVarNameList = {'GPCTD_PRESSURE' 'GPCTD_TEMPERATURE' 'GPCTD_CONDUCTIVITY' ''};

   % retrieve existing sensor data
   sensorStructOld = get_sensor_struct_old(deployJsonData.glider_sensor, deployJsonDirName, gliderVarNameList);
end

if (~isempty(gliderVarNameList))

   % set sensor data structure
   egoVarNameList = {'PRES' 'TEMP' 'CNDC' 'PSAL'};
   paramStructList = repmat(get_param_struct, 1, length(egoVarNameList));
   for idP = 1:length(egoVarNameList)
      egoVarNameListCtd{end+1} = egoVarNameList{idP};
      paramStructList(idP).ego_variable_name = egoVarNameList{idP};
      paramStructList(idP).glider_variable_name = gliderVarNameList{idP};
      if (strcmp(egoVarNameList{idP}, 'PSAL'))
         paramStructList(idP).derivation_comment = 'Not measured by the glider. Calculated by Coriolis';
      end
   end

   sensorStruct = get_sensor_struct;
   sensorStruct.SENSOR = {'CTD_PRES' 'CTD_TEMP' 'CTD_CNDC'};
   sensorStruct.SENSOR_MAKER = {'SBE' 'SBE' 'SBE'};
   sensorStruct.SENSOR_MODEL = {'SBE' 'SBE' 'SBE'};
   sensorStruct.SENSOR_SERIAL_NO = repmat({'9999'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_MOUNT = repmat({'MOUNTED_ON_GLIDER'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_ORIENTATION = repmat({''}, size(sensorStruct.SENSOR));

   sensorStruct.PARAMETER = egoVarNameList;
   sensorStruct.PARAMETER_SENSOR = {'CTD_PRES' 'CTD_TEMP' 'CTD_CNDC' 'CTD_CNDC'};
   sensorStruct.PARAMETER_DATA_MODE = repmat({'R'}, size(sensorStruct.PARAMETER));
   sensorStruct.PARAMETER_UNITS = repmat({''}, size(sensorStruct.PARAMETER));
   sensorStruct.PARAMETER_ACCURACY = repmat({''}, size(sensorStruct.PARAMETER));
   sensorStruct.PARAMETER_RESOLUTION = repmat({''}, size(sensorStruct.PARAMETER));

   sensorStruct.CALIBRATION_COEFFICIENT = [];
   if (~isempty(sensorStructOld))
      if (~isempty(sensorStructOld.CALIBRATION_COEFFICIENT))
         sensorStruct.CALIBRATION_COEFFICIENT = sensorStructOld.CALIBRATION_COEFFICIENT;
      end
   end

   sensorStruct.parametersList = paramStructList;

   % update sensor data structure with existing sensor json file
   sensorStruct = update_sensor_data(sensorStruct, sensorStructOld, a_deploymentDirName, 'CTD_SBE', a_csvFid);

   % generate sensor json file
   outputFileName = [a_deploymentDirName '_CTD_SBE_' sensorStruct.SENSOR_SERIAL_NO{1} '.json'];
   outputFilePathName = [outputDirName outputFileName];
   sensorFileNameList{end+1} = outputFileName;

   ok = write_json_sensor_file(outputFilePathName, sensorStruct);
   if (ok == 0)
      fprintf('ERROR: Error while generating sensor JSON file: %s\n', outputFilePathName);
   end
end

sensorStructOld = [];
gliderVarNameList = [];
if (any(strcmp('LEGATO_PRESSURE', availableParam)) && ...
      any(strcmp('LEGATO_TEMPERATURE', availableParam)) && ...
      any(strcmp('LEGATO_CONDUCTIVITY', availableParam)) && ...
      any(strcmp('LEGATO_CONDTEMP', availableParam)) && ...
      any(strcmp('LEGATO_SALINITY', availableParam)))

   gliderVarNameList = {'LEGATO_PRESSURE' 'LEGATO_TEMPERATURE' 'LEGATO_CONDUCTIVITY' 'LEGATO_CONDTEMP' 'LEGATO_SALINITY'};

   % retrieve existing sensor data
   sensorStructOld = get_sensor_struct_old(deployJsonData.glider_sensor, deployJsonDirName, gliderVarNameList);
end

if (~isempty(gliderVarNameList))

   % set sensor data structure
   egoVarNameList = [{'PRES'} {'TEMP'} {'CNDC'} {'TEMP_CNDC'} {'PSAL'}];
   paramStructList = repmat(get_param_struct, 1, length(egoVarNameList));
   for idP = 1:length(egoVarNameList)
      if (any(strcmp(egoVarNameList{idP}, egoVarNameListCtd)))
         cpt = 2;
         egoVarName = [egoVarNameList{idP} num2str(cpt)];
         while (any(strcmp(egoVarName, egoVarNameListCtd)))
            cpt = cpt + 1;
            egoVarName = [egoVarNameList{idP} num2str(cpt)];
         end
         egoVarNameList{idP} = egoVarName;
      end
      egoVarNameListCtd{end+1} = egoVarNameList{idP};
      paramStructList(idP).ego_variable_name = egoVarNameList{idP};
      paramStructList(idP).glider_variable_name = gliderVarNameList{idP};
      if (strncmp(egoVarNameList{idP}, 'CNDC', length('CNDC')))
         paramStructList(idP).processing_id = 'slope_offset';
      end
   end

   sensorStruct = get_sensor_struct;
   sensorStruct.SENSOR = {'CTD_PRES' 'CTD_TEMP' 'CTD_CNDC'};
   sensorStruct.SENSOR_MAKER = {'RBR' 'RBR' 'RBR'};
   sensorStruct.SENSOR_MODEL = {'RBR_LEGATO3' 'RBR_LEGATO3' 'RBR_LEGATO3'};
   sensorStruct.SENSOR_SERIAL_NO = repmat({'9999'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_MOUNT = repmat({'MOUNTED_ON_GLIDER'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_ORIENTATION = repmat({''}, size(sensorStruct.SENSOR));

   sensorStruct.PARAMETER = egoVarNameList;
   sensorStruct.PARAMETER_SENSOR = {'CTD_PRES' 'CTD_TEMP' 'CTD_CNDC' 'CTD_CNDC' 'CTD_CNDC'};
   sensorStruct.PARAMETER_DATA_MODE = repmat({'R'}, size(sensorStruct.PARAMETER));
   sensorStruct.PARAMETER_UNITS = repmat({''}, size(sensorStruct.PARAMETER));
   sensorStruct.PARAMETER_ACCURACY = repmat({''}, size(sensorStruct.PARAMETER));
   sensorStruct.PARAMETER_RESOLUTION = repmat({''}, size(sensorStruct.PARAMETER));

   sensorStruct.CALIBRATION_COEFFICIENT = [];
   if (~isempty(sensorStructOld))
      if (~isempty(sensorStructOld.CALIBRATION_COEFFICIENT))
         sensorStruct.CALIBRATION_COEFFICIENT = sensorStructOld.CALIBRATION_COEFFICIENT;
      end
   end
   calInfo = [];
   for idC = 1:length(sensorStruct.CALIBRATION_COEFFICIENT)
      if (iscell(sensorStruct.CALIBRATION_COEFFICIENT))
         calCoef = sensorStruct.CALIBRATION_COEFFICIENT{idC};
      else
         calCoef = sensorStruct.CALIBRATION_COEFFICIENT(idC);
      end
      fieldNames = fields(calCoef);
      for idF = 1:length(fieldNames)
         fieldName = fieldNames{idF};
         if (isfield(calCoef.(fieldName), 'Case'))
            calInfo = [calInfo; [{fieldName} {calCoef.(fieldName).Case}]];
         end
      end
   end
   if (isempty(calInfo) || ~any(strcmp(calInfo(:, 1), 'CTD_CNDC') & strcmp(calInfo(:, 2), 'slope_offset')))
      caseStruct = [];
      caseStruct.Case = 'slope_offset';
      caseStruct.SlopeValue = 0.1;
      caseStruct.OffsetValue = 0;
      sensorStruct.CALIBRATION_COEFFICIENT.CTD_CNDC = caseStruct;
   end

   sensorStruct.parametersList = paramStructList;

   % update sensor data structure with existing sensor json file
   sensorStruct = update_sensor_data(sensorStruct, sensorStructOld, a_deploymentDirName, 'CTD_RBR', a_csvFid);

   % generate sensor json file
   outputFileName = [a_deploymentDirName '_CTD_RBR_' sensorStruct.SENSOR_SERIAL_NO{1} '.json'];
   outputFilePathName = [outputDirName outputFileName];
   sensorFileNameList{end+1} = outputFileName;

   ok = write_json_sensor_file(outputFilePathName, sensorStruct);
   if (ok == 0)
      fprintf('ERROR: Error while generating sensor JSON file: %s\n', outputFilePathName);
   end
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% OPTODE_DOXY

sensorStruct = get_sensor_struct;
sensorStructOld = [];
gliderVarNameList = [];
egoVarNameListDo = [];
if (any(strcmp('AROD_FT_TEMP', availableParam)) && ...
      any(strcmp('AROD_FT_DO', availableParam)))

   egoVarNameList = {'TEMP_DOXY' 'MOLAR_DOXY'};
   gliderVarNameList = {'AROD_FT_TEMP' 'AROD_FT_DO'};

   % retrieve existing sensor data
   sensorStructOld = get_sensor_struct_old(deployJsonData.glider_sensor, deployJsonDirName, gliderVarNameList);

   sensorStruct.SENSOR = {'OPTODE_DOXY'};
   sensorStruct.SENSOR_MAKER = {'JAC'};
   sensorStruct.SENSOR_MODEL = {'ARO_FT'};
   sensorStruct.SENSOR_SERIAL_NO = repmat({'9999'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_MOUNT = repmat({'MOUNTED_ON_GLIDER'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_ORIENTATION = repmat({''}, size(sensorStruct.SENSOR));

elseif (any(strcmp('LEGATO_CODA_CORR_PHASE', availableParam)) && ...
      any(strcmp('LEGATO_CODA_TEMPERATURE', availableParam)) && ...
      any(strcmp('LEGATO_CODA_DO', availableParam)))

   egoVarNameList = {'DPHASE_DOXY' 'TEMP_DOXY' 'MOLAR_DOXY'};
   gliderVarNameList = {'LEGATO_CODA_CORR_PHASE' 'LEGATO_CODA_TEMPERATURE' 'LEGATO_CODA_DO'};

   % retrieve existing sensor data
   sensorStructOld = get_sensor_struct_old(deployJsonData.glider_sensor, deployJsonDirName, gliderVarNameList);

   sensorStruct.SENSOR = {'OPTODE_DOXY'};
   sensorStruct.SENSOR_MAKER = {'RBR'};
   sensorStruct.SENSOR_MODEL = {'RBR_CODA_T_ODO'};
   sensorStruct.SENSOR_SERIAL_NO = repmat({'9999'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_MOUNT = repmat({'MOUNTED_ON_GLIDER'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_ORIENTATION = repmat({''}, size(sensorStruct.SENSOR));
end

if (~isempty(gliderVarNameList))

   % set sensor data structure
   paramStructList = repmat(get_param_struct, 1, length(egoVarNameList));
   for idP = 1:length(egoVarNameList)
      egoVarNameListDo{end+1} = egoVarNameList{idP};
      paramStructList(idP).ego_variable_name = egoVarNameList{idP};
      paramStructList(idP).glider_variable_name = gliderVarNameList{idP};
   end

   sensorStruct.PARAMETER = egoVarNameList;
   sensorStruct.PARAMETER_SENSOR = repmat({'OPTODE_DOXY'}, 1, length(sensorStruct.PARAMETER));
   sensorStruct.PARAMETER_DATA_MODE = repmat({'R'}, 1, length(sensorStruct.PARAMETER));
   sensorStruct.PARAMETER_UNITS = repmat({''}, 1, length(sensorStruct.PARAMETER));
   sensorStruct.PARAMETER_ACCURACY = repmat({''}, 1, length(sensorStruct.PARAMETER));
   sensorStruct.PARAMETER_RESOLUTION = repmat({''}, 1, length(sensorStruct.PARAMETER));

   sensorStruct.CALIBRATION_COEFFICIENT = [];
   caseStruct = [];
   caseStruct.Case = '201_201_301';
   caseStruct.DoxyCalibRefSalinity = 0;
   sensorStruct.CALIBRATION_COEFFICIENT.OPTODE_DOXY = caseStruct;

   sensorStruct.PARAMETER{end+1} = 'DOXY';
   egoVarNameListDo{end+1} = 'DOXY';
   sensorStruct.PARAMETER_SENSOR{end+1} = 'OPTODE_DOXY';
   sensorStruct.PARAMETER_DATA_MODE{end+1} = 'R';
   sensorStruct.PARAMETER_UNITS{end+1} = '';
   sensorStruct.PARAMETER_ACCURACY{end+1} = '';
   sensorStruct.PARAMETER_RESOLUTION{end+1} = '';

   paramStructList(end+1) = get_param_struct;
   paramStructList(end).ego_variable_name = 'DOXY';
   paramStructList(end).derivation_comment = 'Not measured by the glider. Calculated by Coriolis';
   paramStructList(end).processing_id = '201_201_301';

   sensorStruct.parametersList = paramStructList;

   % update sensor data structure with existing sensor json file
   sensorStruct = update_sensor_data(sensorStruct, sensorStructOld, a_deploymentDirName, 'OPTODE_DOXY', a_csvFid);

   % generate sensor json file
   outputFileName = [a_deploymentDirName '_OPTODE_DOXY_' sensorStruct.SENSOR_SERIAL_NO{1} '.json'];
   outputFilePathName = [outputDirName outputFileName];
   sensorFileNameList{end+1} = outputFileName;

   ok = write_json_sensor_file(outputFilePathName, sensorStruct);
   if (ok == 0)
      fprintf('ERROR: Error while generating sensor JSON file: %s\n', outputFilePathName);
   end
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% IDO_DOXY

sensorStruct = get_sensor_struct;
sensorStructOld = [];
gliderVarNameList = [];
if (any(strcmp('GPCTD_DOF', availableParam)))

   egoVarNameList = {'FREQUENCY_DOXY'};
   gliderVarNameList = {'GPCTD_DOF'};

   % retrieve existing sensor data
   sensorStructOld = get_sensor_struct_old(deployJsonData.glider_sensor, deployJsonDirName, gliderVarNameList);

   sensorStruct.SENSOR = {'IDO_DOXY'};
   sensorStruct.SENSOR_MAKER = {'SBE'};
   sensorStruct.SENSOR_MODEL = {'SBE43F_IDO'};
   sensorStruct.SENSOR_SERIAL_NO = repmat({'9999'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_MOUNT = repmat({'MOUNTED_ON_GLIDER'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_ORIENTATION = repmat({''}, size(sensorStruct.SENSOR));
end

if (~isempty(gliderVarNameList))

   % set sensor data structure
   paramStructList = repmat(get_param_struct, 1, length(egoVarNameList));
   for idP = 1:length(egoVarNameList)
      egoVarNameListDo{end+1} = egoVarNameList{idP};
      paramStructList(idP).ego_variable_name = egoVarNameList{idP};
      paramStructList(idP).glider_variable_name = gliderVarNameList{idP};
   end

   sensorStruct.PARAMETER = egoVarNameList;
   sensorStruct.PARAMETER_SENSOR = repmat({'IDO_DOXY'}, 1, length(sensorStruct.PARAMETER));
   sensorStruct.PARAMETER_DATA_MODE = repmat({'R'}, 1, length(sensorStruct.PARAMETER));
   sensorStruct.PARAMETER_UNITS = repmat({''}, 1, length(sensorStruct.PARAMETER));
   sensorStruct.PARAMETER_ACCURACY = repmat({''}, 1, length(sensorStruct.PARAMETER));
   sensorStruct.PARAMETER_RESOLUTION = repmat({''}, 1, length(sensorStruct.PARAMETER));

   sensorStruct.CALIBRATION_COEFFICIENT = [];
   if (~isempty(sensorStructOld))
      if (~isempty(sensorStructOld.CALIBRATION_COEFFICIENT))
         sensorStruct.CALIBRATION_COEFFICIENT = sensorStructOld.CALIBRATION_COEFFICIENT;
      end
   end
   calInfo = [];
   for idC = 1:length(sensorStruct.CALIBRATION_COEFFICIENT)
      if (iscell(sensorStruct.CALIBRATION_COEFFICIENT))
         calCoef = sensorStruct.CALIBRATION_COEFFICIENT{idC};
      else
         calCoef = sensorStruct.CALIBRATION_COEFFICIENT(idC);
      end
      fieldNames = fields(calCoef);
      for idF = 1:length(fieldNames)
         fieldName = fieldNames{idF};
         if (isfield(calCoef.(fieldName), 'Case'))
            calInfo = [calInfo; [{fieldName} {calCoef.(fieldName).Case}]];
         end
      end
   end
   if (~isempty(calInfo) && any(strcmp(calInfo(:, 1), 'IDO_DOXY') & strcmp(calInfo(:, 2), '102_207_206')))
      egoVarName = 'DOXY';
      if (any(strcmp(egoVarName, egoVarNameListDo)))
         cpt = 2;
         egoVarName = [egoVarName num2str(cpt)];
         while (any(strcmp(egoVarName, egoVarNameListDo)))
            cpt = cpt + 1;
            egoVarName = [egoVarNameList{idP} num2str(cpt)];
         end
      end
      sensorStruct.PARAMETER{end+1} = egoVarName;
      sensorStruct.PARAMETER_SENSOR{end+1} = 'IDO_DOXY';
      sensorStruct.PARAMETER_DATA_MODE{end+1} = 'R';
      sensorStruct.PARAMETER_UNITS{end+1} = '';
      sensorStruct.PARAMETER_ACCURACY{end+1} = '';
      sensorStruct.PARAMETER_RESOLUTION{end+1} = '';

      paramStructList(end+1) = get_param_struct;
      paramStructList(end).ego_variable_name = egoVarName;
      paramStructList(end).derivation_comment = 'Not measured by the glider. Calculated by Coriolis';
      paramStructList(end).processing_id = '102_207_206';
   end

   sensorStruct.parametersList = paramStructList;

   % update sensor data structure with existing sensor json file
   sensorStruct = update_sensor_data(sensorStruct, sensorStructOld, a_deploymentDirName, 'IDO_DOXY', a_csvFid);

   % generate sensor json file
   outputFileName = [a_deploymentDirName '_IDO_DOXY_' sensorStruct.SENSOR_SERIAL_NO{1} '.json'];
   outputFilePathName = [outputDirName outputFileName];
   sensorFileNameList{end+1} = outputFileName;

   ok = write_json_sensor_file(outputFilePathName, sensorStruct);
   if (ok == 0)
      fprintf('ERROR: Error while generating sensor JSON file: %s\n', outputFilePathName);
   end
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% FLNTU

sensorStruct = get_sensor_struct;
sensorStructOld = [];
gliderVarNameList = [];
if (any(strcmp('FLNTU_CHL_COUNT', availableParam)) && ...
      any(strcmp('FLNTU_CHL_SCALED', availableParam)) && ...
      any(strcmp('FLNTU_NTU_COUNT', availableParam)) && ...
      any(strcmp('FLNTU_NTU_SCALED', availableParam)))

   egoVarNameList = {'FLUORESCENCE_CHLA' 'CHLA' 'SIDE_SCATTERING_TURBIDITY' 'TURBIDITY'};
   gliderVarNameList = {'FLNTU_CHL_COUNT' 'FLNTU_CHL_SCALED' 'FLNTU_NTU_COUNT' 'FLNTU_NTU_SCALED'};

   % retrieve existing sensor data
   sensorStructOld = get_sensor_struct_old(deployJsonData.glider_sensor, deployJsonDirName, gliderVarNameList);

   sensorStruct.SENSOR = {'FLUOROMETER_CHLA' 'BACKSCATTERINGMETER_TURBIDITY'};
   sensorStruct.SENSOR_MAKER = {'WETLABS' 'WETLABS'};
   sensorStruct.SENSOR_MODEL = {'ECO_FLNTU' 'ECO_FLNTU'};
   sensorStruct.SENSOR_SERIAL_NO = repmat({'9999'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_MOUNT = repmat({'MOUNTED_ON_GLIDER'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_ORIENTATION = repmat({''}, size(sensorStruct.SENSOR));

   sensorStruct.PARAMETER = {'FLUORESCENCE_CHLA' 'CHLA' 'SIDE_SCATTERING_TURBIDITY' 'TURBIDITY'};
   sensorStruct.PARAMETER_SENSOR = {'FLUOROMETER_CHLA' 'FLUOROMETER_CHLA' 'BACKSCATTERINGMETER_TURBIDITY' 'BACKSCATTERINGMETER_TURBIDITY'};
   sensorStruct.PARAMETER_DATA_MODE = repmat({'R'}, 1, length(sensorStruct.PARAMETER));
   sensorStruct.PARAMETER_UNITS = repmat({''}, 1, length(sensorStruct.PARAMETER));
   sensorStruct.PARAMETER_ACCURACY = repmat({''}, 1, length(sensorStruct.PARAMETER));
   sensorStruct.PARAMETER_RESOLUTION = repmat({''}, 1, length(sensorStruct.PARAMETER));
end

if (~isempty(gliderVarNameList))

   % set sensor data structure
   paramStructList = repmat(get_param_struct, 1, length(egoVarNameList));
   for idP = 1:length(egoVarNameList)
      paramStructList(idP).ego_variable_name = egoVarNameList{idP};
      paramStructList(idP).glider_variable_name = gliderVarNameList{idP};
   end

   sensorStruct.CALIBRATION_COEFFICIENT = [];
   if (~isempty(sensorStructOld))
      if (~isempty(sensorStructOld.CALIBRATION_COEFFICIENT))
         sensorStruct.CALIBRATION_COEFFICIENT = sensorStructOld.CALIBRATION_COEFFICIENT;
      end
   end

   sensorStruct.parametersList = paramStructList;

   % update sensor data structure with existing sensor json file
   sensorStruct = update_sensor_data(sensorStruct, sensorStructOld, a_deploymentDirName, 'FLNTU', a_csvFid);

   % generate sensor json file
   outputFileName = [a_deploymentDirName '_ECO_FLNTU_' sensorStruct.SENSOR_SERIAL_NO{1} '.json'];
   outputFilePathName = [outputDirName outputFileName];
   sensorFileNameList{end+1} = outputFileName;

   ok = write_json_sensor_file(outputFilePathName, sensorStruct);
   if (ok == 0)
      fprintf('ERROR: Error while generating sensor JSON file: %s\n', outputFilePathName);
   end
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% FLBBCD

sensorStruct = get_sensor_struct;
sensorStructOld = [];
gliderVarNameList = [];
if (any(strcmp('FLBBCD_CHL_COUNT', availableParam)) && ...
      any(strcmp('FLBBCD_CHL_SCALED', availableParam)) && ...
      any(strcmp('FLBBCD_BB_700_COUNT', availableParam)) && ...
      any(strcmp('FLBBCD_BB_700_SCALED', availableParam)) && ...
      any(strcmp('FLBBCD_CDOM_COUNT', availableParam)) && ...
      any(strcmp('FLBBCD_CDOM_SCALED', availableParam)))

   egoVarNameList = {'FLUORESCENCE_CHLA' 'CHLA' 'BETA_BACKSCATTERING700' 'BBP700' 'FLUORESCENCE_CDOM' 'CDOM'};
   gliderVarNameList = {'FLBBCD_CHL_COUNT' 'FLBBCD_CHL_SCALED' 'FLBBCD_BB_700_COUNT' 'FLBBCD_BB_700_SCALED' 'FLBBCD_CDOM_COUNT' 'FLBBCD_CDOM_SCALED'};

   % retrieve existing sensor data
   sensorStructOld = get_sensor_struct_old(deployJsonData.glider_sensor, deployJsonDirName, gliderVarNameList);

   sensorStruct.SENSOR = {'FLUOROMETER_CHLA' 'BACKSCATTERINGMETER_BBP700' 'FLUOROMETER_CDOM'};
   sensorStruct.SENSOR_MAKER = {'WETLABS' 'WETLABS' 'WETLABS'};
   sensorStruct.SENSOR_MODEL = {'ECO_FLBBCD' 'ECO_FLBBCD' 'ECO_FLBBCD'};
   sensorStruct.SENSOR_SERIAL_NO = repmat({'9999'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_MOUNT = repmat({'MOUNTED_ON_GLIDER'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_ORIENTATION = repmat({''}, size(sensorStruct.SENSOR));

   sensorStruct.PARAMETER = {'FLUORESCENCE_CHLA' 'CHLA' 'BETA_BACKSCATTERING700' 'BBP700' 'FLUORESCENCE_CDOM' 'CDOM'};
   sensorStruct.PARAMETER_SENSOR = {'FLUOROMETER_CHLA' 'FLUOROMETER_CHLA' 'BACKSCATTERINGMETER_BBP700' 'BACKSCATTERINGMETER_BBP700' 'FLUOROMETER_CDOM' 'FLUOROMETER_CDOM'};
   sensorStruct.PARAMETER_DATA_MODE = repmat({'R'}, 1, length(sensorStruct.PARAMETER));
   sensorStruct.PARAMETER_UNITS = repmat({''}, 1, length(sensorStruct.PARAMETER));
   sensorStruct.PARAMETER_ACCURACY = repmat({''}, 1, length(sensorStruct.PARAMETER));
   sensorStruct.PARAMETER_RESOLUTION = repmat({''}, 1, length(sensorStruct.PARAMETER));
end

if (~isempty(gliderVarNameList))

   % set sensor data structure
   paramStructList = repmat(get_param_struct, 1, length(egoVarNameList));
   for idP = 1:length(egoVarNameList)
      paramStructList(idP).ego_variable_name = egoVarNameList{idP};
      paramStructList(idP).glider_variable_name = gliderVarNameList{idP};
   end

   sensorStruct.CALIBRATION_COEFFICIENT = [];
   if (~isempty(sensorStructOld))
      if (~isempty(sensorStructOld.CALIBRATION_COEFFICIENT))
         sensorStruct.CALIBRATION_COEFFICIENT = sensorStructOld.CALIBRATION_COEFFICIENT;
      end
   end

   sensorStruct.parametersList = paramStructList;

   % update sensor data structure with existing sensor json file
   sensorStruct = update_sensor_data(sensorStruct, sensorStructOld, a_deploymentDirName, 'FLBBCD', a_csvFid);

   % generate sensor json file
   outputFileName = [a_deploymentDirName '_ECO_FLBBCD_' sensorStruct.SENSOR_SERIAL_NO{1} '.json'];
   outputFilePathName = [outputDirName outputFileName];
   sensorFileNameList{end+1} = outputFileName;

   ok = write_json_sensor_file(outputFilePathName, sensorStruct);
   if (ok == 0)
      fprintf('ERROR: Error while generating sensor JSON file: %s\n', outputFilePathName);
   end
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% FLBBPE

sensorStruct = get_sensor_struct;
sensorStructOld = [];
gliderVarNameList = [];
if (any(strcmp('FLBBPE_CHL_COUNT', availableParam)) && ...
      any(strcmp('FLBBPE_CHL_SCALED', availableParam)) && ...
      any(strcmp('FLBBPE_BB_700_COUNT', availableParam)) && ...
      any(strcmp('FLBBPE_BB_700_SCALED', availableParam)) && ...
      any(strcmp('FLBBPE_PE_COUNT', availableParam)) && ...
      any(strcmp('FLBBPE_PE_SCALED', availableParam)))

   egoVarNameList = {'FLUORESCENCE_CHLA' 'CHLA' 'BETA_BACKSCATTERING700' 'BBP700' 'FLUORESCENCE_PE' 'PE'};
   gliderVarNameList = {'FLBBPE_CHL_COUNT' 'FLBBPE_CHL_SCALED' 'FLBBPE_BB_700_COUNT' 'FLBBPE_BB_700_SCALED' 'FLBBPE_PE_COUNT' 'FLBBPE_PE_SCALED'};

   % retrieve existing sensor data
   sensorStructOld = get_sensor_struct_old(deployJsonData.glider_sensor, deployJsonDirName, gliderVarNameList);

   sensorStruct.SENSOR = {'FLUOROMETER_CHLA' 'BACKSCATTERINGMETER_BBP700' 'FLUOROMETER_PE'};
   sensorStruct.SENSOR_MAKER = {'WETLABS' 'WETLABS' 'WETLABS'};
   sensorStruct.SENSOR_MODEL = {'ECO_FLBBPE' 'ECO_FLBBPE' 'ECO_FLBBPE'};
   sensorStruct.SENSOR_SERIAL_NO = repmat({'9999'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_MOUNT = repmat({'MOUNTED_ON_GLIDER'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_ORIENTATION = repmat({''}, size(sensorStruct.SENSOR));

   sensorStruct.PARAMETER = {'FLUORESCENCE_CHLA' 'CHLA' 'BETA_BACKSCATTERING700' 'BBP700' 'FLUORESCENCE_PE' 'PE'};
   sensorStruct.PARAMETER_SENSOR = {'FLUOROMETER_CHLA' 'FLUOROMETER_CHLA' 'BACKSCATTERINGMETER_BBP700' 'BACKSCATTERINGMETER_BBP700' 'FLUOROMETER_PE' 'FLUOROMETER_PE'};
   sensorStruct.PARAMETER_DATA_MODE = repmat({'R'}, 1, length(sensorStruct.PARAMETER));
   sensorStruct.PARAMETER_UNITS = repmat({''}, 1, length(sensorStruct.PARAMETER));
   sensorStruct.PARAMETER_ACCURACY = repmat({''}, 1, length(sensorStruct.PARAMETER));
   sensorStruct.PARAMETER_RESOLUTION = repmat({''}, 1, length(sensorStruct.PARAMETER));
end

if (~isempty(gliderVarNameList))

   % set sensor data structure
   paramStructList = repmat(get_param_struct, 1, length(egoVarNameList));
   for idP = 1:length(egoVarNameList)
      paramStructList(idP).ego_variable_name = egoVarNameList{idP};
      paramStructList(idP).glider_variable_name = gliderVarNameList{idP};
   end

   sensorStruct.CALIBRATION_COEFFICIENT = [];
   if (~isempty(sensorStructOld))
      if (~isempty(sensorStructOld.CALIBRATION_COEFFICIENT))
         sensorStruct.CALIBRATION_COEFFICIENT = sensorStructOld.CALIBRATION_COEFFICIENT;
      end
   end

   sensorStruct.parametersList = paramStructList;

   % update sensor data structure with existing sensor json file
   sensorStruct = update_sensor_data(sensorStruct, sensorStructOld, a_deploymentDirName, 'FLBBPE', a_csvFid);

   % generate sensor json file
   outputFileName = [a_deploymentDirName '_ECO_FLBBPE_' sensorStruct.SENSOR_SERIAL_NO{1} '.json'];
   outputFilePathName = [outputDirName outputFileName];
   sensorFileNameList{end+1} = outputFileName;

   ok = write_json_sensor_file(outputFilePathName, sensorStruct);
   if (ok == 0)
      fprintf('ERROR: Error while generating sensor JSON file: %s\n', outputFilePathName);
   end
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% OCR

sensorStruct = get_sensor_struct;
sensorStructOld = [];
gliderVarNameList = [];
if (any(strcmp('OCR504_Ed1', availableParam)) && ...
      any(strcmp('OCR504_Ed2', availableParam)) && ...
      any(strcmp('OCR504_Ed3', availableParam)) && ...
      any(strcmp('OCR504_Ed4', availableParam)))

   egoVarNameList = {'DOWN_IRRADIANCE380' 'DOWN_IRRADIANCE490' 'DOWN_IRRADIANCE532' 'DOWNWELLING_PAR'};
   gliderVarNameList = {'OCR504_Ed1' 'OCR504_Ed2' 'OCR504_Ed3' 'OCR504_Ed4'};

   % retrieve existing sensor data
   sensorStructOld = get_sensor_struct_old(deployJsonData.glider_sensor, deployJsonDirName, gliderVarNameList);

   sensorStruct.SENSOR = {'RADIOMETER_DOWN_IRR380' 'RADIOMETER_DOWN_IRR490' 'RADIOMETER_DOWN_IRR532' 'RADIOMETER_PAR'};
   sensorStruct.SENSOR_MAKER = {'SATLANTIC' 'SATLANTIC' 'SATLANTIC' 'SATLANTIC'};
   sensorStruct.SENSOR_MODEL = {'SATLANTIC_OCR504_ICSW' 'SATLANTIC_OCR504_ICSW' 'SATLANTIC_OCR504_ICSW' 'SATLANTIC_OCR504_ICSW'};
   sensorStruct.SENSOR_SERIAL_NO = repmat({'9999'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_MOUNT = repmat({'MOUNTED_ON_GLIDER'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_ORIENTATION = repmat({''}, size(sensorStruct.SENSOR));

   sensorStruct.PARAMETER = {'DOWN_IRRADIANCE380' 'DOWN_IRRADIANCE490' 'DOWN_IRRADIANCE532' 'DOWNWELLING_PAR'};
   sensorStruct.PARAMETER_SENSOR = {'RADIOMETER_DOWN_IRR380' 'RADIOMETER_DOWN_IRR490' 'RADIOMETER_DOWN_IRR532' 'RADIOMETER_PAR'};
   sensorStruct.PARAMETER_DATA_MODE = repmat({'R'}, 1, length(sensorStruct.PARAMETER));
   sensorStruct.PARAMETER_UNITS = repmat({''}, 1, length(sensorStruct.PARAMETER));
   sensorStruct.PARAMETER_ACCURACY = repmat({''}, 1, length(sensorStruct.PARAMETER));
   sensorStruct.PARAMETER_RESOLUTION = repmat({''}, 1, length(sensorStruct.PARAMETER));
end

if (~isempty(gliderVarNameList))

   % set sensor data structure
   paramStructList = repmat(get_param_struct, 1, length(egoVarNameList));
   for idP = 1:length(egoVarNameList)
      paramStructList(idP).ego_variable_name = egoVarNameList{idP};
      paramStructList(idP).glider_variable_name = gliderVarNameList{idP};
      if (ismember(egoVarNameList{idP}, {'DOWN_IRRADIANCE380' 'DOWN_IRRADIANCE490' 'DOWN_IRRADIANCE532'}))
         paramStructList(idP).processing_id = 'slope_offset';
      end
   end

   sensorStruct.CALIBRATION_COEFFICIENT = [];
   if (~isempty(sensorStructOld))
      if (~isempty(sensorStructOld.CALIBRATION_COEFFICIENT))
         sensorStruct.CALIBRATION_COEFFICIENT = sensorStructOld.CALIBRATION_COEFFICIENT;
      end
   end
   calInfo = [];
   for idC = 1:length(sensorStruct.CALIBRATION_COEFFICIENT)
      if (iscell(sensorStruct.CALIBRATION_COEFFICIENT))
         calCoef = sensorStruct.CALIBRATION_COEFFICIENT{idC};
      else
         calCoef = sensorStruct.CALIBRATION_COEFFICIENT(idC);
      end
      fieldNames = fields(calCoef);
      for idF = 1:length(fieldNames)
         fieldName = fieldNames{idF};
         if (isfield(calCoef.(fieldName), 'Case'))
            calInfo = [calInfo; [{fieldName} {calCoef.(fieldName).Case}]];
         end
      end
   end
   if (isempty(calInfo) || ~any(strcmp(calInfo(:, 1), 'RADIOMETER_DOWN_IRR380') & strcmp(calInfo(:, 2), 'slope_offset')))
      caseStruct = [];
      caseStruct.Case = 'slope_offset';
      caseStruct.SlopeValue = 0.01;
      caseStruct.OffsetValue = 0;
      sensorStruct.CALIBRATION_COEFFICIENT.RADIOMETER_DOWN_IRR380 = caseStruct;
   end
   if (isempty(calInfo) || ~any(strcmp(calInfo(:, 1), 'RADIOMETER_DOWN_IRR490') & strcmp(calInfo(:, 2), 'slope_offset')))
      caseStruct = [];
      caseStruct.Case = 'slope_offset';
      caseStruct.SlopeValue = 0.01;
      caseStruct.OffsetValue = 0;
      sensorStruct.CALIBRATION_COEFFICIENT.RADIOMETER_DOWN_IRR490 = caseStruct;
   end
   if (isempty(calInfo) || ~any(strcmp(calInfo(:, 1), 'RADIOMETER_DOWN_IRR532') & strcmp(calInfo(:, 2), 'slope_offset')))
      caseStruct = [];
      caseStruct.Case = 'slope_offset';
      caseStruct.SlopeValue = 0.01;
      caseStruct.OffsetValue = 0;
      sensorStruct.CALIBRATION_COEFFICIENT.RADIOMETER_DOWN_IRR532 = caseStruct;
   end

   sensorStruct.parametersList = paramStructList;

   % update sensor data structure with existing sensor json file
   sensorStruct = update_sensor_data(sensorStruct, sensorStructOld, a_deploymentDirName, 'OCR', a_csvFid);

   % generate sensor json file
   outputFileName = [a_deploymentDirName '_OCR_' sensorStruct.SENSOR_SERIAL_NO{1} '.json'];
   outputFilePathName = [outputDirName outputFileName];
   sensorFileNameList{end+1} = outputFileName;

   ok = write_json_sensor_file(outputFilePathName, sensorStruct);
   if (ok == 0)
      fprintf('ERROR: Error while generating sensor JSON file: %s\n', outputFilePathName);
   end
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% duplicate the json deployment file in the output directory
copyfile(deployJsonFilePathName, outputDirName);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% update json sensor file names in json deployment file

[~, fileName, fileExt] = fileparts(deployJsonFilePathName);
deployJsonFilePathNameNew = [outputDirName fileName fileExt];

% read JSON deployment file
fIdIn = fopen(deployJsonFilePathNameNew, 'r');
if (fIdIn == -1)
   fprintf('ERROR: While openning file : %s\n', deployJsonFilePathNameNew);
   return
end

% read the data
deployJsonStr = [];
while (1)
   line = fgetl(fIdIn);
   if (line == -1)
      break
   end
   deployJsonStr{end+1} = line;
end
fclose(fIdIn);

% update file contents
idF = cellfun(@(x) strfind(deployJsonStr, x), {'"glider_sensor"'}, 'UniformOutput', 0);
idF1 = find(~cellfun(@isempty, idF{:}));
idF = cellfun(@(x) strfind(deployJsonStr, x), {']'}, 'UniformOutput', 0);
idF2 = find(~cellfun(@isempty, idF{:}));
idF2 = idF2(find(idF2 > idF1, 1));

newLines = [];
for idF = 1:length(sensorFileNameList)
   newLines{end+1} = sprintf('\t\t{');
   newLines{end+1} = sprintf('\t\t\t"sensor_file_name": "%s"', sensorFileNameList{idF});
   if (idF < length(sensorFileNameList))
      newLines{end+1} = sprintf('\t\t},');
   else
      newLines{end+1} = sprintf('\t\t}');
   end
end
deployJsonStr2 = cell(1, idF1+length(newLines)+length(deployJsonStr)-idF2+1);
deployJsonStr2(1:idF1) = deployJsonStr(1:idF1);
deployJsonStr2(idF1+1:idF1+1+length(newLines)-1) = newLines;
deployJsonStr2(idF1+1+length(newLines):end) = deployJsonStr(idF2:end);

% write updated file file
fIdOut = fopen(deployJsonFilePathNameNew, 'wt');
if (fIdOut == -1)
   fprintf('ERROR: While creating file : %s\n', deployJsonFilePathNameNew);
   return
end

fprintf(fIdOut, '%s\n', deployJsonStr2{:});

fclose(fIdOut);

return

% ------------------------------------------------------------------------------
% Look for sensor file with at least one glider variable.
%
% SYNTAX :
% [o_sensorStruct] = get_sensor_struct_old(a_sensorFiles, a_deployJsonDirName, a_gliderVarNameList)
%
% INPUT PARAMETERS :
%   a_sensorFiles       : JSON sensor file list
%   a_deployJsonDirName : JSON directory of the deployment
%   a_gliderVarNameList : list of glider variables
%
% OUTPUT PARAMETERS :
%   o_sensorStruct : contents of found sensor file
%
% EXAMPLES :
%
% SEE ALSO :
% AUTHOR : Jean-Philippe Rannou (Capgemini) (jean.philippe.rannou@partenaire-exterieur.ifremer.fr)
% ------------------------------------------------------------------------------
% RELEASES :
%   12/08/2023 - RNU - creation
% ------------------------------------------------------------------------------
function [o_sensorStruct] = get_sensor_struct_old(a_sensorFiles, a_deployJsonDirName, a_gliderVarNameList)

% output parameters initialization
o_sensorStruct = [];


for idF = 1:length(a_sensorFiles)
   sensorData = gl_load_json([a_deployJsonDirName a_sensorFiles(idF).sensor_file_name]);
   for idV = 1:length(a_gliderVarNameList)
      idF1 = cellfun(@(x) strfind({sensorData.parametersList.glider_variable_name}, x), {a_gliderVarNameList{idV}}, 'UniformOutput', 0);
      if (any(~cellfun(@isempty, idF1{:})))
         o_sensorStruct = sensorData;
         break
      end
   end
   if (~isempty(o_sensorStruct))
      break
   end
end

return

% ------------------------------------------------------------------------------
% Update sensor data structure from already existing one.
%
% SYNTAX :
% [o_sensorStruct] = update_sensor_data(a_sensorStruct, a_sensorStructOld, ...
%   a_deployName, a_sensorLabel, a_csvFid)
%
% INPUT PARAMETERS :
%   a_sensorStruct    : input sensor data
%   a_sensorStructOld : already existing sensor data
%   a_deployName      : name of the deployment
%   a_sensorLabel     : name of the sensor
%   a_csvFid          : output CSv file Id
%
% OUTPUT PARAMETERS :
%   o_sensorStruct : output sensor data
%
% EXAMPLES :
%
% SEE ALSO :
% AUTHOR : Jean-Philippe Rannou (Capgemini) (jean.philippe.rannou@partenaire-exterieur.ifremer.fr)
% ------------------------------------------------------------------------------
% RELEASES :
%   12/04/2023 - RNU - creation
% ------------------------------------------------------------------------------
function [o_sensorStruct] = update_sensor_data(a_sensorStruct, a_sensorStructOld, ...
   a_deployName, a_sensorLabel, a_csvFid)

% output parameters initialization
o_sensorStruct = a_sensorStruct;


if (isempty(a_sensorStructOld))
   return
end

% check format version
if (~strcmp(a_sensorStruct.EGO_format_version, a_sensorStructOld.EGO_format_version))
   fprintf(a_csvFid, 'ERROR; %s; %s; EGO_format_version differ\n', a_deployName, a_sensorLabel);
end

% check SENSOR data
if (length(a_sensorStruct.SENSOR) ~= length(a_sensorStructOld.SENSOR))
   % fprintf('WARNING: %s: %s: Number of SENSOR differ\n', a_deployName, a_sensorLabel);
end
for idS = 1:length(a_sensorStruct.SENSOR)
   sensorName = a_sensorStruct.SENSOR{idS};
   idF = find(strcmp(sensorName, a_sensorStructOld.SENSOR));
   if (isempty(idF))
      % fprintf('WARNING: %s: %s: %s sensor is missing in existing file\n', a_deployName, a_sensorLabel, sensorName);
   else
      if (~strcmp(a_sensorStruct.SENSOR_MAKER{idS}, a_sensorStructOld.SENSOR_MAKER{idF}))
         fprintf(a_csvFid, 'INFO; %s; %s; SENSOR; %s; SENSOR_MAKER updated;%s;%s\n', ...
            a_deployName, a_sensorLabel, sensorName, ...
            a_sensorStruct.SENSOR_MAKER{idS}, a_sensorStructOld.SENSOR_MAKER{idF});
         o_sensorStruct.SENSOR_MAKER{idS} = a_sensorStructOld.SENSOR_MAKER{idF};
      end
      if (~strcmp(a_sensorStruct.SENSOR_MODEL{idS}, a_sensorStructOld.SENSOR_MODEL{idF}))
         if (~ismember(a_sensorStructOld.SENSOR_MODEL{idF}, {'ECO_FLBB'}))
            fprintf(a_csvFid, 'INFO; %s; %s; SENSOR; %s; SENSOR_MODEL updated;%s;%s\n', ...
               a_deployName, a_sensorLabel, sensorName, ...
               a_sensorStruct.SENSOR_MODEL{idS}, a_sensorStructOld.SENSOR_MODEL{idF});
            o_sensorStruct.SENSOR_MODEL{idS} = a_sensorStructOld.SENSOR_MODEL{idF};
         end
      end
      if (~strcmp(a_sensorStruct.SENSOR_SERIAL_NO{idS}, a_sensorStructOld.SENSOR_SERIAL_NO{idF}))
         if (~ismember(a_sensorStructOld.SENSOR_SERIAL_NO{idF}, {'XXXX', '99999', '0000'}))
            fprintf(a_csvFid, 'INFO; %s; %s; SENSOR; %s; SENSOR_SERIAL_NO updated;%s;%s\n', ...
               a_deployName, a_sensorLabel, sensorName, ...
               a_sensorStruct.SENSOR_SERIAL_NO{idS}, a_sensorStructOld.SENSOR_SERIAL_NO{idF});
            o_sensorStruct.SENSOR_SERIAL_NO{idS} = a_sensorStructOld.SENSOR_SERIAL_NO{idF};
         end
      end
      if (~strcmp(a_sensorStruct.SENSOR_MOUNT{idS}, a_sensorStructOld.SENSOR_MOUNT{idF}))
         if ~(strcmp(a_sensorStruct.SENSOR_MOUNT{idS}, 'MOUNTED_ON_GLIDER') && strcmp(a_sensorStructOld.SENSOR_MOUNT{idF}, ''))
            fprintf(a_csvFid, 'INFO; %s; %s; SENSOR; %s; SENSOR_MOUNT updated;%s;%s\n', ...
               a_deployName, a_sensorLabel, sensorName, ...
               a_sensorStruct.SENSOR_MOUNT{idS}, a_sensorStructOld.SENSOR_MOUNT{idF});
            o_sensorStruct.SENSOR_MOUNT{idS} = a_sensorStructOld.SENSOR_MOUNT{idF};
         end
      end
      if (~strcmp(a_sensorStruct.SENSOR_ORIENTATION{idS}, a_sensorStructOld.SENSOR_ORIENTATION{idF}))
         fprintf(a_csvFid, 'INFO; %s; %s; SENSOR; %s; SENSOR_ORIENTATION updated;%s;%s\n', ...
            a_deployName, a_sensorLabel, sensorName, ...
            a_sensorStruct.SENSOR_ORIENTATION{idS}, a_sensorStructOld.SENSOR_ORIENTATION{idF});
         o_sensorStruct.SENSOR_ORIENTATION{idS} = a_sensorStructOld.SENSOR_ORIENTATION{idF};
      end
   end
end

% check PARAMETER data
if (length(a_sensorStruct.PARAMETER) ~= length(a_sensorStructOld.PARAMETER))
   % fprintf('WARNING: %s: %s: Number of PARAMETER differ\n', a_deployName, a_sensorLabel);
end
for idP = 1:length(a_sensorStruct.PARAMETER)
   paramName = a_sensorStruct.PARAMETER{idP};
   idF = find(strcmp(paramName, a_sensorStructOld.PARAMETER));
   if (isempty(idF))
      % fprintf('WARNING: %s: %s: %s parameter is missing in existing file\n', a_deployName, a_sensorLabel, paramName);
   else
      if (~strcmp(a_sensorStruct.PARAMETER_SENSOR{idP}, a_sensorStructOld.PARAMETER_SENSOR{idF}))
         fprintf(a_csvFid, 'INFO; %s; %s; PARAMETER; %s; PARAMETER_SENSOR updated;%s;%s\n', ...
            a_deployName, a_sensorLabel, paramName, ...
            a_sensorStruct.PARAMETER_SENSOR{idP}, a_sensorStructOld.PARAMETER_SENSOR{idF});
         o_sensorStruct.PARAMETER_SENSOR{idP} = a_sensorStructOld.PARAMETER_SENSOR{idF};
      end
      if (~strcmp(a_sensorStruct.PARAMETER_DATA_MODE{idP}, a_sensorStructOld.PARAMETER_DATA_MODE{idF}))
         fprintf(a_csvFid, 'INFO; %s; %s; PARAMETER; %s; PARAMETER_DATA_MODE updated;%s;%s\n', ...
            a_deployName, a_sensorLabel, paramName, ...
            a_sensorStruct.PARAMETER_DATA_MODE{idP}, a_sensorStructOld.PARAMETER_DATA_MODE{idF});
         o_sensorStruct.PARAMETER_DATA_MODE{idP} = a_sensorStructOld.PARAMETER_DATA_MODE{idF};
      end
      if (~strcmp(a_sensorStruct.PARAMETER_UNITS{idP}, a_sensorStructOld.PARAMETER_UNITS{idF}))
         if (~isempty(a_sensorStructOld.PARAMETER_UNITS{idF}))
            if (~isempty(a_sensorStructOld.PARAMETER_ACCURACY{idF}) || ~isempty(a_sensorStructOld.PARAMETER_RESOLUTION{idF}))
               fprintf(a_csvFid, 'INFO; %s; %s; PARAMETER; %s; PARAMETER_UNITS updated;%s;%s\n', ...
                  a_deployName, a_sensorLabel, paramName, ...
                  a_sensorStruct.PARAMETER_UNITS{idP}, a_sensorStructOld.PARAMETER_UNITS{idF});
               o_sensorStruct.PARAMETER_UNITS{idP} = a_sensorStructOld.PARAMETER_UNITS{idF};
            end
         end
      end
      if (~strcmp(a_sensorStruct.PARAMETER_ACCURACY{idP}, a_sensorStructOld.PARAMETER_ACCURACY{idF}))
         fprintf(a_csvFid, 'INFO; %s; %s; PARAMETER; %s; PARAMETER_ACCURACY updated;%s;%s\n', ...
            a_deployName, a_sensorLabel, paramName, ...
            a_sensorStruct.PARAMETER_ACCURACY{idP}, a_sensorStructOld.PARAMETER_ACCURACY{idF});
         o_sensorStruct.PARAMETER_ACCURACY{idP} = a_sensorStructOld.PARAMETER_ACCURACY{idF};
      end
      if (~strcmp(a_sensorStruct.PARAMETER_RESOLUTION{idP}, a_sensorStructOld.PARAMETER_RESOLUTION{idF}))
         fprintf(a_csvFid, 'INFO; %s; %s; PARAMETER; %s; PARAMETER_RESOLUTION updated;%s;%s\n', ...
            a_deployName, a_sensorLabel, paramName, ...
            a_sensorStruct.PARAMETER_RESOLUTION{idP}, a_sensorStructOld.PARAMETER_RESOLUTION{idF});
         o_sensorStruct.PARAMETER_RESOLUTION{idP} = a_sensorStructOld.PARAMETER_RESOLUTION{idF};
      end
   end
end

% check PARAMETER attributes data
for idP = 1:length(a_sensorStruct.PARAMETER)
   paramName = a_sensorStruct.PARAMETER{idP};
   idF1 = find(strcmp(paramName, {a_sensorStruct.parametersList.ego_variable_name}));
   idF2 = find(strcmp(paramName, {a_sensorStructOld.parametersList.ego_variable_name}));
   if (isempty(idF2))
      % fprintf('WARNING: %s: %s: %s parameter is missing in existing file\n', a_deployName, a_sensorLabel, paramName);
   else
      if (~strcmp(a_sensorStruct.parametersList(idF1).glider_variable_name, a_sensorStructOld.parametersList(idF2).glider_variable_name))
         fprintf(a_csvFid, 'INFO; %s; %s; PARAMETER; %s; glider_variable_name updated;%s;%s\n', ...
            a_deployName, a_sensorLabel, paramName, ...
            a_sensorStruct.parametersList(idF1).glider_variable_name, a_sensorStructOld.parametersList(idF2).glider_variable_name);
         o_sensorStruct.parametersList(idF1).glider_variable_name = a_sensorStructOld.parametersList(idF2).glider_variable_name;
      end
      if (~strcmp(a_sensorStruct.parametersList(idF1).comment, a_sensorStructOld.parametersList(idF2).comment))
         fprintf(a_csvFid, 'INFO; %s; %s; PARAMETER; %s; comment updated;%s;%s\n', ...
            a_deployName, a_sensorLabel, paramName, ...
            a_sensorStruct.parametersList(idF1).comment, a_sensorStructOld.parametersList(idF2).comment);
         o_sensorStruct.parametersList(idF1).comment = a_sensorStructOld.parametersList(idF2).comment;
      end
      if (~strcmp(a_sensorStruct.parametersList(idF1).cell_methods, a_sensorStructOld.parametersList(idF2).cell_methods))
         fprintf(a_csvFid, 'INFO; %s; %s; PARAMETER; %s; cell_methods updated;%s;%s\n', ...
            a_deployName, a_sensorLabel, paramName, ...
            a_sensorStruct.parametersList(idF1).cell_methods, a_sensorStructOld.parametersList(idF2).cell_methods);
         o_sensorStruct.parametersList(idF1).cell_methods = a_sensorStructOld.parametersList(idF2).cell_methods;
      end
      if (~strcmp(a_sensorStruct.parametersList(idF1).reference_scale, a_sensorStructOld.parametersList(idF2).reference_scale))
         fprintf(a_csvFid, 'INFO; %s; %s; PARAMETER; %s; reference_scale updated;%s;%s\n', ...
            a_deployName, a_sensorLabel, paramName, ...
            a_sensorStruct.parametersList(idF1).reference_scale, a_sensorStructOld.parametersList(idF2).reference_scale);
         o_sensorStruct.parametersList(idF1).reference_scale = a_sensorStructOld.parametersList(idF2).reference_scale;
      end
      if (~strcmp(a_sensorStruct.parametersList(idF1).derivation_equation, a_sensorStructOld.parametersList(idF2).derivation_equation))
         if (~strcmp(a_sensorStructOld.parametersList(idF2).derivation_equation, 'r'))
            fprintf(a_csvFid, 'INFO; %s; %s; PARAMETER; %s; derivation_equation updated;"%s";"%s"\n', ...
               a_deployName, a_sensorLabel, paramName, ...
               a_sensorStruct.parametersList(idF1).derivation_equation, a_sensorStructOld.parametersList(idF2).derivation_equation);
            o_sensorStruct.parametersList(idF1).derivation_equation = a_sensorStructOld.parametersList(idF2).derivation_equation;
         end
      end
      if (~strcmp(a_sensorStruct.parametersList(idF1).derivation_coefficient, a_sensorStructOld.parametersList(idF2).derivation_coefficient))
         if (~strcmp(a_sensorStructOld.parametersList(idF2).derivation_coefficient, 'Not measured by the glider. Calculated by Coriolis'))
            fprintf(a_csvFid, 'INFO; %s; %s; PARAMETER; %s; derivation_coefficient updated;"%s";"%s"\n', ...
               a_deployName, a_sensorLabel, paramName, ...
               a_sensorStruct.parametersList(idF1).derivation_coefficient, a_sensorStructOld.parametersList(idF2).derivation_coefficient);
            o_sensorStruct.parametersList(idF1).derivation_coefficient = a_sensorStructOld.parametersList(idF2).derivation_coefficient;
         end
      end
      if (~strcmp(a_sensorStruct.parametersList(idF1).derivation_comment, a_sensorStructOld.parametersList(idF2).derivation_comment))
         if (~isempty(a_sensorStructOld.parametersList(idF2).derivation_comment))
            comment = a_sensorStructOld.parametersList(idF2).derivation_comment;
            comment = regexprep(comment, char(9), ' ');
            comment = regexprep(comment, char(10), ' ');
            comment = regexprep(comment, char(13), ' ');
            fprintf(a_csvFid, 'INFO; %s; %s; PARAMETER; %s; derivation_comment updated;%s;%s\n', ...
               a_deployName, a_sensorLabel, paramName, ...
               a_sensorStruct.parametersList(idF1).derivation_comment, comment);
            o_sensorStruct.parametersList(idF1).derivation_comment = comment;
         end
      end
      if (~strcmp(a_sensorStruct.parametersList(idF1).derivation_date, a_sensorStructOld.parametersList(idF2).derivation_date))
         fprintf(a_csvFid, 'INFO; %s; %s; PARAMETER; %s; derivation_date updated;%s;%s\n', ...
            a_deployName, a_sensorLabel, paramName, ...
            a_sensorStruct.parametersList(idF1).derivation_date, a_sensorStructOld.parametersList(idF2).derivation_date);
         o_sensorStruct.parametersList(idF1).derivation_date = a_sensorStructOld.parametersList(idF2).derivation_date;
      end
      if (~strcmp(a_sensorStruct.parametersList(idF1).processing_id, a_sensorStructOld.parametersList(idF2).processing_id))
         fprintf(a_csvFid, 'INFO; %s; %s; PARAMETER; %s; processing_id updated;%s;%s\n', ...
            a_deployName, a_sensorLabel, paramName, ...
            a_sensorStruct.parametersList(idF1).processing_id, a_sensorStructOld.parametersList(idF2).processing_id);
         o_sensorStruct.parametersList(idF1).processing_id = a_sensorStructOld.parametersList(idF2).processing_id;
      end
   end
end

% check PARAMETER attributes data
% for idP = 1:length(a_sensorStructOld.PARAMETER)
%    paramName = a_sensorStructOld.PARAMETER{idP};
%    if (~any(strcmp(paramName, {a_sensorStruct.parametersList.ego_variable_name})))
%       o_sensorStruct.parametersList(end+1) = a_sensorStructOld.parametersList(idP);
%       fprintf('INFO: %s: %s: PARAMETER: %s: parameter added\n', ...
%          a_deployName, a_sensorLabel, paramName);
%    end
% end

% check CALIBRATION_COEFFICIENT data
if (length(a_sensorStruct.CALIBRATION_COEFFICIENT) ~= length(a_sensorStructOld.CALIBRATION_COEFFICIENT))
   % fprintf('WARNING: %s: %s: Number of CALIBRATION_COEFFICIENT differ\n', a_deployName, a_sensorLabel);
end

return

% ------------------------------------------------------------------------------
% Generate sensor JSON file.
%
% SYNTAX :
% [o_ok] = write_json_sensor_file(a_jsonOutPathFile, a_sensorData)
%
% INPUT PARAMETERS :
%   a_jsonOutPathFile : file path name of the created json file
%   a_sensorData      : sensor information
%
% OUTPUT PARAMETERS :
%   o_ok : processing report flag
%
% EXAMPLES :
%
% SEE ALSO :
% AUTHOR : Jean-Philippe Rannou (Capgemini) (jean.philippe.rannou@partenaire-exterieur.ifremer.fr)
% ------------------------------------------------------------------------------
% RELEASES :
%   12/04/2023 - RNU - creation
% ------------------------------------------------------------------------------
function [o_ok] = write_json_sensor_file(a_jsonOutPathFile, a_sensorData)

% output parameters initialization
o_ok = 0;


% create the json output file
fidOut = fopen(a_jsonOutPathFile, 'wt');
if (fidOut == -1)
   fprintf('ERROR: unable to create json output file: %s\n', a_jsonOutPathFile);
   return
end

fprintf(fidOut, '{\n');

fprintf(fidOut, '\t"EGO_format_version": "%s",\n\n', a_sensorData.EGO_format_version);

fieldNames = [{'SENSOR'} {'SENSOR_MAKER'} {'SENSOR_MODEL'} {'SENSOR_SERIAL_NO'} {'SENSOR_MOUNT'} {'SENSOR_ORIENTATION'}];
tabs = [{'\t\t\t\t'} {'\t\t\t'} {'\t\t\t'} {'\t\t'} {'\t\t\t'} {'\t'}];
for idF = 1:length(fieldNames)
   field = fieldNames{idF};
   fprintf(fidOut, ['\t"%s"' tabs{idF} ': ["'], field);
   for idS = 1:length(a_sensorData.(field))
      if (idS < length(a_sensorData.(field)))
         fprintf(fidOut, '%s", "', a_sensorData.(field){idS});
      else
         fprintf(fidOut, '%s"], \n', a_sensorData.(field){idS});
      end
   end
end
fprintf(fidOut, '\n');

fieldNames = [{'PARAMETER'} {'PARAMETER_SENSOR'} {'PARAMETER_DATA_MODE'} {'PARAMETER_UNITS'} {'PARAMETER_ACCURACY'} {'PARAMETER_RESOLUTION'}];
tabs = [{'\t\t\t\t'} {'\t\t'} {'\t'} {'\t\t'} {'\t'} {'\t'}];
for idF = 1:length(fieldNames)
   field = fieldNames{idF};
   fprintf(fidOut, ['\t"%s"' tabs{idF} ': ["'], field);
   for idS = 1:length(a_sensorData.(field))
      if (idS < length(a_sensorData.(field)))
         fprintf(fidOut, '%s", "', a_sensorData.(field){idS});
      else
         fprintf(fidOut, '%s"], \n', a_sensorData.(field){idS});
      end
   end
end

fprintf(fidOut, '\n');

if (isempty(a_sensorData.CALIBRATION_COEFFICIENT))
   fprintf(fidOut, '\t"CALIBRATION_COEFFICIENT": [],\n');
else
   fprintf(fidOut, '\t"CALIBRATION_COEFFICIENT": [\n');
   calibStr = jsonencode(a_sensorData.CALIBRATION_COEFFICIENT, 'PrettyPrint', true);
   calibStr = splitlines(calibStr);
   if (strcmp(calibStr{1}, '['))
      calibStr(1) = [];
      calibStr(end) = [];
   end
   fprintf(fidOut, '\t\t%s\n', calibStr{:});
   fprintf(fidOut, '\t],\n');
end

fprintf(fidOut, '\n');

fprintf(fidOut, '\t"parametersList": [\n');

fieldNames = [ ...
   {'ego_variable_name'}, ...
   {'glider_variable_name'}, ...
   {'comment'}, ...
   {'cell_methods'}, ...
   {'reference_scale'}, ...
   {'derivation_equation'}, ...
   {'derivation_coefficient'}, ...
   {'derivation_comment'}, ...
   {'derivation_date'}, ...
   {'processing_id'}, ...
   ];
tabs = [{'\t\t'} {'\t'} {'\t\t\t\t'} {'\t\t\t'} {'\t\t'} {'\t'} {''} {'\t'} {'\t\t'} {'\t\t\t'}];
for idP = 1:length(a_sensorData.parametersList)
   fprintf(fidOut, '\t\t{\n');
   paramStruct = a_sensorData.parametersList(idP);
   for idF = 1:length(fieldNames)
      field = fieldNames{idF};
      if (idF < length(fieldNames))
         fprintf(fidOut, ['\t\t\t"%s"' tabs{idF} ': "%s",\n'], field, paramStruct.(field));
      else
         fprintf(fidOut, ['\t\t\t"%s"' tabs{idF} ': "%s"\n'], field, paramStruct.(field));
      end
      if (ismember(idF, [5 9]))
         fprintf(fidOut, '\n');
      end
   end
   if (idP < length(a_sensorData.parametersList))
      fprintf(fidOut, '\t\t},\n');
   else
      fprintf(fidOut, '\t\t}\n');
   end
end

fprintf(fidOut, '\t]\n');

fprintf(fidOut, '}\n');

fclose(fidOut);

o_ok = 1;

return

% ------------------------------------------------------------------------------
% Create sensor structure.
%
% SYNTAX :
% o_sensorStruct = get_sensor_struct
%
% INPUT PARAMETERS :
%
% OUTPUT PARAMETERS :
%
% EXAMPLES :
%
% SEE ALSO :
% AUTHOR : Jean-Philippe Rannou (Capgemini) (jean.philippe.rannou@partenaire-exterieur.ifremer.fr)
% ------------------------------------------------------------------------------
% RELEASES :
%   12/04/2023 - RNU - creation
% ------------------------------------------------------------------------------
function o_sensorStruct = get_sensor_struct

o_sensorStruct = struct( ...
   'EGO_format_version', '1.4', ...
   'SENSOR', '', ...
   'SENSOR_MAKER', '', ...
   'SENSOR_MODEL', '', ...
   'SENSOR_SERIAL_NO', '', ...
   'SENSOR_MOUNT', '', ...
   'SENSOR_ORIENTATION', '', ...
   'PARAMETER', '', ...
   'PARAMETER_SENSOR', '', ...
   'PARAMETER_DATA_MODE', '', ...
   'PARAMETER_UNITS', '', ...
   'PARAMETER_ACCURACY', '', ...
   'PARAMETER_RESOLUTION', '', ...
   'CALIBRATION_COEFFICIENT', '', ...
   'parametersList', '');

return

% ------------------------------------------------------------------------------
% Create parameter structure.
%
% SYNTAX :
% o_paramStruct = get_param_struct
%
% INPUT PARAMETERS :
%
% OUTPUT PARAMETERS :
%
% EXAMPLES :
%
% SEE ALSO :
% AUTHOR : Jean-Philippe Rannou (Capgemini) (jean.philippe.rannou@partenaire-exterieur.ifremer.fr)
% ------------------------------------------------------------------------------
% RELEASES :
%   12/04/2023 - RNU - creation
% ------------------------------------------------------------------------------
function o_paramStruct = get_param_struct

o_paramStruct = struct( ...
   'ego_variable_name', '', ...
   'glider_variable_name', '', ...
   'comment', '', ...
   'cell_methods', '', ...
   'reference_scale', '', ...
   'derivation_equation', '', ...
   'derivation_coefficient', '', ...
   'derivation_comment', '', ...
   'derivation_date', '', ...
   'processing_id', '');

return
