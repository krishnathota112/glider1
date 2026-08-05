% ------------------------------------------------------------------------------
% Generate json sensor files from available data (and existing sensor files).
%
% SYNTAX :
%   gl_create_json_sensor_files_slocum or
%   gl_create_json_sensor_files_slocum('data', 'crate_mooset00_38')
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
%   10/24/2023 - RNU - creation
% ------------------------------------------------------------------------------
function gl_create_json_sensor_files_slocum(varargin)

% top directory of the input deployment directories
INPUT_DATA_DIRECTORY = 'C:\Users\jprannou\_DATA\GLIDER\slocum\';

% top directory of the output
OUTPUT_DATA_DIRECTORY = 'C:\Users\jprannou\_DATA\GLIDER\out\';

% directory to store the log file
DIR_LOG_FILE = 'C:\Users\jprannou\_RNU\Glider\work\log\';

% directory to store the CSV file
DIR_CSV_FILE = 'C:\Users\jprannou\_RNU\Glider\work\csv\';

% available data mat file
AVAILABLE_DATA_FILE_NAME = 'C:\Users\jprannou\_RNU\Glider\work\slocum_available_data.mat';

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
logFile = [DIR_LOG_FILE '/' 'gl_create_json_sensor_files_slocum_' deploymentDir '_' datestr(now, 'yyyymmddTHHMMSS') '.log'];
diary(logFile);
tic;

% create the CSV output file
csvFile = [DIR_CSV_FILE '/' 'gl_create_json_sensor_files_slocum_' deploymentDir '_' datestr(now, 'yyyymmddTHHMMSS') '.csv'];
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
%   10/24/2023 - RNU - creation
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
   [availableParam, availableData] = gl_get_available_data_slocum(a_deployInputDirName, a_deploymentDirName);
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
if (any(strcmp('sci_water_pressure', availableParam)) && ...
      any(strcmp('sci_water_temp', availableParam)) && ...
      any(strcmp('sci_water_cond', availableParam)))

   gliderVarNameList = {'sci_water_pressure' 'sci_water_temp' 'sci_water_cond' ''};

   % retrieve existing sensor data
   sensorStructOld = get_sensor_struct_old(deployJsonData.glider_sensor, deployJsonDirName, gliderVarNameList);

elseif (any(strcmp('m_water_pressure', availableParam)) && ...
      any(strcmp('m_water_temp', availableParam)) && ...
      any(strcmp('m_water_cond', availableParam)))

   gliderVarNameList = {'m_water_pressure' 'm_water_temp' 'm_water_cond' ''};

   % retrieve existing sensor data
   sensorStructOld = get_sensor_struct_old(deployJsonData.glider_sensor, deployJsonDirName, gliderVarNameList);

elseif (any(strcmp('gld_dup_sci_water_pressure', availableParam)) && ...
      any(strcmp('gld_dup_sci_water_temp', availableParam)) && ...
      any(strcmp('gld_dup_sci_water_cond', availableParam)))

   gliderVarNameList = {'gld_dup_sci_water_pressure' 'm_water_temp' 'm_water_cond' ''};

   % retrieve existing sensor data
   sensorStructOld = get_sensor_struct_old(deployJsonData.glider_sensor, deployJsonDirName, gliderVarNameList);

elseif (any(strcmp('m_water_pressure', availableParam)) && ...
      any(strcmp('water_temp', availableParam)) && ...
      any(strcmp('water_cond', availableParam)))

   gliderVarNameList = {'m_water_pressure' 'water_temp' 'water_cond' ''};

   % retrieve existing sensor data
   sensorStructOld = get_sensor_struct_old(deployJsonData.glider_sensor, deployJsonDirName, gliderVarNameList);
end

if (~isempty(gliderVarNameList))

   % set sensor data structure
   egoVarNameList = [{'PRES'} {'TEMP'} {'CNDC'} {'PSAL'}];
   paramStructList = repmat(get_param_struct, 1, length(egoVarNameList));
   for idP = 1:length(egoVarNameList)
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

   sensorStruct.PARAMETER = {'PRES' 'TEMP' 'CNDC' 'PSAL'};
   sensorStruct.PARAMETER_SENSOR = {'CTD_PRES' 'CTD_TEMP' 'CTD_CNDC' 'CTD_CNDC'};
   sensorStruct.PARAMETER_DATA_MODE = repmat({'R'}, 1, length(sensorStruct.PARAMETER));
   sensorStruct.PARAMETER_UNITS = repmat({''}, 1, length(sensorStruct.PARAMETER));
   sensorStruct.PARAMETER_ACCURACY = repmat({''}, 1, length(sensorStruct.PARAMETER));
   sensorStruct.PARAMETER_RESOLUTION = repmat({''}, 1, length(sensorStruct.PARAMETER));

   sensorStruct.CALIBRATION_COEFFICIENT = [];

   sensorStruct.parametersList = paramStructList;

   % update sensor data structure with existing sensor json file
   sensorStruct = update_sensor_data(sensorStruct, sensorStructOld, a_deploymentDirName, 'CTD', a_csvFid);

   % generate sensor json file
   outputFileName = [a_deploymentDirName '_CTD_' sensorStruct.SENSOR_SERIAL_NO{1} '.json'];
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
if (any(strcmp('sci_oxy4_c1rph', availableParam)) && ...
      any(strcmp('sci_oxy4_c2rph', availableParam)) && ...
      any(strcmp('sci_oxy4_tcphase', availableParam)) && ...
      any(strcmp('sci_oxy4_temp', availableParam)) && ...
      any(strcmp('sci_oxy4_oxygen', availableParam)))

   egoVarNameList = {'C1PHASE_DOXY' 'C2PHASE_DOXY' 'TPHASE_DOXY' 'TEMP_DOXY' 'MOLAR_DOXY'};
   gliderVarNameList = {'sci_oxy4_c1rph' 'sci_oxy4_c2rph' 'sci_oxy4_tcphase' 'sci_oxy4_temp' 'sci_oxy4_oxygen'};

   % retrieve existing sensor data
   sensorStructOld = get_sensor_struct_old(deployJsonData.glider_sensor, deployJsonDirName, gliderVarNameList);

   sensorStruct.SENSOR = {'OPTODE_DOXY'};
   sensorStruct.SENSOR_MAKER = {'AANDERAA'};
   sensorStruct.SENSOR_MODEL = {'AANDERAA_OPTODE_4330'};
   sensorStruct.SENSOR_SERIAL_NO = repmat({'9999'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_MOUNT = repmat({'MOUNTED_ON_GLIDER'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_ORIENTATION = repmat({''}, size(sensorStruct.SENSOR));

elseif (any(strcmp('sci_oxy3835_wphase_bphase', availableParam)) && ...
      any(strcmp('sci_oxy3835_wphase_dphase', availableParam)) && ...
      any(strcmp('sci_oxy3835_wphase_rphase', availableParam)) && ...
      any(strcmp('sci_oxy3835_wphase_temp', availableParam)) && ...
      any(strcmp('sci_oxy3835_wphase_oxygen', availableParam)))

   egoVarNameList = {'BPHASE_DOXY' 'DPHASE_DOXY' 'RPHASE_DOXY' 'TEMP_DOXY' 'MOLAR_DOXY'};
   gliderVarNameList = {'sci_oxy3835_wphase_bphase' 'sci_oxy3835_wphase_dphase' 'sci_oxy3835_wphase_rphase' 'sci_oxy3835_wphase_temp' 'sci_oxy3835_wphase_oxygen'};

   % retrieve existing sensor data
   sensorStructOld = get_sensor_struct_old(deployJsonData.glider_sensor, deployJsonDirName, gliderVarNameList);

   sensorStruct.SENSOR = {'OPTODE_DOXY'};
   sensorStruct.SENSOR_MAKER = {'AANDERAA'};
   sensorStruct.SENSOR_MODEL = {'AANDERAA_OPTODE_3835'};
   sensorStruct.SENSOR_SERIAL_NO = repmat({'9999'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_MOUNT = repmat({'MOUNTED_ON_GLIDER'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_ORIENTATION = repmat({''}, size(sensorStruct.SENSOR));

elseif (any(strcmp('sci_oxy3835_wphase_bphase', availableParam)) && ...
      any(strcmp('sci_oxy3835_wphase_dphase', availableParam)) && ...
      any(strcmp('sci_oxy3835_wphase_temp', availableParam)) && ...
      any(strcmp('sci_oxy3835_wphase_oxygen', availableParam)))

   egoVarNameList = {'BPHASE_DOXY' 'DPHASE_DOXY' 'TEMP_DOXY' 'MOLAR_DOXY'};
   gliderVarNameList = {'sci_oxy3835_wphase_bphase' 'sci_oxy3835_wphase_dphase' 'sci_oxy3835_wphase_temp' 'sci_oxy3835_wphase_oxygen'};

   % retrieve existing sensor data
   sensorStructOld = get_sensor_struct_old(deployJsonData.glider_sensor, deployJsonDirName, gliderVarNameList);

   sensorStruct.SENSOR = {'OPTODE_DOXY'};
   sensorStruct.SENSOR_MAKER = {'AANDERAA'};
   sensorStruct.SENSOR_MODEL = {'AANDERAA_OPTODE_3835'};
   sensorStruct.SENSOR_SERIAL_NO = repmat({'9999'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_MOUNT = repmat({'MOUNTED_ON_GLIDER'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_ORIENTATION = repmat({''}, size(sensorStruct.SENSOR));

elseif (any(strcmp('sci_oxy3835_wphase_bphase', availableParam)) && ...
      any(strcmp('sci_oxy3835_wphase_rphase', availableParam)) && ...
      any(strcmp('sci_oxy3835_wphase_temp', availableParam)) && ...
      any(strcmp('sci_oxy3835_wphase_oxygen', availableParam)))

   egoVarNameList = {'BPHASE_DOXY' 'RPHASE_DOXY' 'TEMP_DOXY' 'MOLAR_DOXY'};
   gliderVarNameList = {'sci_oxy3835_wphase_bphase' 'sci_oxy3835_wphase_rphase' 'sci_oxy3835_wphase_temp' 'sci_oxy3835_wphase_oxygen'};

   % retrieve existing sensor data
   sensorStructOld = get_sensor_struct_old(deployJsonData.glider_sensor, deployJsonDirName, gliderVarNameList);

   sensorStruct.SENSOR = {'OPTODE_DOXY'};
   sensorStruct.SENSOR_MAKER = {'AANDERAA'};
   sensorStruct.SENSOR_MODEL = {'AANDERAA_OPTODE_3835'};
   sensorStruct.SENSOR_SERIAL_NO = repmat({'9999'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_MOUNT = repmat({'MOUNTED_ON_GLIDER'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_ORIENTATION = repmat({''}, size(sensorStruct.SENSOR));

elseif (any(strcmp('sci_oxy3835_wphase_dphase', availableParam)) && ...
      any(strcmp('sci_oxy3835_wphase_temp', availableParam)) && ...
      any(strcmp('sci_oxy3835_wphase_oxygen', availableParam)))

   egoVarNameList = {'DPHASE_DOXY' 'TEMP_DOXY' 'MOLAR_DOXY'};
   gliderVarNameList = {'sci_oxy3835_wphase_dphase' 'sci_oxy3835_wphase_temp' 'sci_oxy3835_wphase_oxygen'};

   % retrieve existing sensor data
   sensorStructOld = get_sensor_struct_old(deployJsonData.glider_sensor, deployJsonDirName, gliderVarNameList);

   sensorStruct.SENSOR = {'OPTODE_DOXY'};
   sensorStruct.SENSOR_MAKER = {'AANDERAA'};
   sensorStruct.SENSOR_MODEL = {'AANDERAA_OPTODE_3835'};
   sensorStruct.SENSOR_SERIAL_NO = repmat({'9999'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_MOUNT = repmat({'MOUNTED_ON_GLIDER'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_ORIENTATION = repmat({''}, size(sensorStruct.SENSOR));

elseif (any(strcmp('sci_oxy3835_wphase_bphase', availableParam)) && ...
      any(strcmp('sci_oxy3835_wphase_rphase', availableParam)) && ...
      any(strcmp('sci_oxy3835_wphase_oxygen', availableParam)))

   egoVarNameList = {'BPHASE_DOXY' 'RPHASE_DOXY' 'MOLAR_DOXY'};
   gliderVarNameList = {'sci_oxy3835_wphase_bphase' 'sci_oxy3835_wphase_rphase' 'sci_oxy3835_wphase_oxygen'};

   % retrieve existing sensor data
   sensorStructOld = get_sensor_struct_old(deployJsonData.glider_sensor, deployJsonDirName, gliderVarNameList);

   sensorStruct.SENSOR = {'OPTODE_DOXY'};
   sensorStruct.SENSOR_MAKER = {'AANDERAA'};
   sensorStruct.SENSOR_MODEL = {'AANDERAA_OPTODE_3835'};
   sensorStruct.SENSOR_SERIAL_NO = repmat({'9999'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_MOUNT = repmat({'MOUNTED_ON_GLIDER'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_ORIENTATION = repmat({''}, size(sensorStruct.SENSOR));

elseif (any(strcmp('sci_oxy3835_wphase_bphase', availableParam)) && ...
      any(strcmp('sci_oxy3835_wphase_temp', availableParam)) && ...
      any(strcmp('sci_oxy3835_wphase_oxygen', availableParam)))

   egoVarNameList = {'BPHASE_DOXY' 'TEMP_DOXY' 'MOLAR_DOXY'};
   gliderVarNameList = {'sci_oxy3835_wphase_bphase' 'sci_oxy3835_wphase_temp' 'sci_oxy3835_wphase_oxygen'};

   % retrieve existing sensor data
   sensorStructOld = get_sensor_struct_old(deployJsonData.glider_sensor, deployJsonDirName, gliderVarNameList);

   sensorStruct.SENSOR = {'OPTODE_DOXY'};
   sensorStruct.SENSOR_MAKER = {'AANDERAA'};
   sensorStruct.SENSOR_MODEL = {'AANDERAA_OPTODE_3835'};
   sensorStruct.SENSOR_SERIAL_NO = repmat({'9999'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_MOUNT = repmat({'MOUNTED_ON_GLIDER'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_ORIENTATION = repmat({''}, size(sensorStruct.SENSOR));

elseif (any(strcmp('sci_oxy3835_wphase_bphase', availableParam)) && ...
      any(strcmp('sci_oxy3835_wphase_oxygen', availableParam)))

   egoVarNameList = {'BPHASE_DOXY' 'MOLAR_DOXY'};
   gliderVarNameList = {'sci_oxy3835_wphase_bphase' 'sci_oxy3835_wphase_oxygen'};

   % retrieve existing sensor data
   sensorStructOld = get_sensor_struct_old(deployJsonData.glider_sensor, deployJsonDirName, gliderVarNameList);

   sensorStruct.SENSOR = {'OPTODE_DOXY'};
   sensorStruct.SENSOR_MAKER = {'AANDERAA'};
   sensorStruct.SENSOR_MODEL = {'AANDERAA_OPTODE_3835'};
   sensorStruct.SENSOR_SERIAL_NO = repmat({'9999'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_MOUNT = repmat({'MOUNTED_ON_GLIDER'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_ORIENTATION = repmat({''}, size(sensorStruct.SENSOR));

elseif (any(strcmp('sci_oxy3835_wphase_temp', availableParam)) && ...
      any(strcmp('sci_oxy3835_wphase_oxygen', availableParam)))

   egoVarNameList = {'TEMP_DOXY' 'MOLAR_DOXY'};
   gliderVarNameList = {'sci_oxy3835_wphase_temp' 'sci_oxy3835_wphase_oxygen'};

   % retrieve existing sensor data
   sensorStructOld = get_sensor_struct_old(deployJsonData.glider_sensor, deployJsonDirName, gliderVarNameList);

   sensorStruct.SENSOR = {'OPTODE_DOXY'};
   sensorStruct.SENSOR_MAKER = {'AANDERAA'};
   sensorStruct.SENSOR_MODEL = {'AANDERAA_OPTODE_3835'};
   sensorStruct.SENSOR_SERIAL_NO = repmat({'9999'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_MOUNT = repmat({'MOUNTED_ON_GLIDER'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_ORIENTATION = repmat({''}, size(sensorStruct.SENSOR));

elseif (any(strcmp('sci_oxy3835_temp', availableParam)) && ...
      any(strcmp('sci_oxy3835_oxygen', availableParam)))

   egoVarNameList = {'TEMP_DOXY' 'MOLAR_DOXY'};
   gliderVarNameList = {'sci_oxy3835_temp' 'sci_oxy3835_oxygen'};

   % retrieve existing sensor data
   sensorStructOld = get_sensor_struct_old(deployJsonData.glider_sensor, deployJsonDirName, gliderVarNameList);

   sensorStruct.SENSOR = {'OPTODE_DOXY'};
   sensorStruct.SENSOR_MAKER = {'AANDERAA'};
   sensorStruct.SENSOR_MODEL = {'AANDERAA_OPTODE_3835'};
   sensorStruct.SENSOR_SERIAL_NO = repmat({'9999'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_MOUNT = repmat({'MOUNTED_ON_GLIDER'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_ORIENTATION = repmat({''}, size(sensorStruct.SENSOR));

elseif (any(strcmp('sci_oxy4_tcphase', availableParam)) && ...
      any(strcmp('sci_oxy4_oxygen', availableParam)))

   egoVarNameList = {'TPHASE_DOXY' 'MOLAR_DOXY'};
   gliderVarNameList = {'sci_oxy4_tcphase' 'sci_oxy4_oxygen'};

   % retrieve existing sensor data
   sensorStructOld = get_sensor_struct_old(deployJsonData.glider_sensor, deployJsonDirName, gliderVarNameList);

   sensorStruct.SENSOR = {'OPTODE_DOXY'};
   sensorStruct.SENSOR_MAKER = {'AANDERAA'};
   sensorStruct.SENSOR_MODEL = {'AANDERAA_OPTODE_4330'};
   sensorStruct.SENSOR_SERIAL_NO = repmat({'9999'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_MOUNT = repmat({'MOUNTED_ON_GLIDER'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_ORIENTATION = repmat({''}, size(sensorStruct.SENSOR));

elseif (any(strcmp('sci_oxy4_temp', availableParam)) && ...
      any(strcmp('sci_oxy4_oxygen', availableParam)))

   egoVarNameList = {'TEMP_DOXY' 'MOLAR_DOXY'};
   gliderVarNameList = {'sci_oxy4_temp' 'sci_oxy4_oxygen'};

   % retrieve existing sensor data
   sensorStructOld = get_sensor_struct_old(deployJsonData.glider_sensor, deployJsonDirName, gliderVarNameList);

   sensorStruct.SENSOR = {'OPTODE_DOXY'};
   sensorStruct.SENSOR_MAKER = {'AANDERAA'};
   sensorStruct.SENSOR_MODEL = {'AANDERAA_OPTODE_4330'};
   sensorStruct.SENSOR_SERIAL_NO = repmat({'9999'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_MOUNT = repmat({'MOUNTED_ON_GLIDER'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_ORIENTATION = repmat({''}, size(sensorStruct.SENSOR));

elseif (any(strcmp('sci_rinkoii_temp', availableParam)) && ...
      any(strcmp('sci_rinkoii_voltage', availableParam)) && ...
      any(strcmp('sci_rinkoii_do', availableParam)))

   egoVarNameList = {'TEMP_DOXY' 'VOLTAGE_DOXY' 'MOLAR_DOXY'};
   gliderVarNameList = {'sci_rinkoii_temp' 'sci_rinkoii_voltage' 'sci_rinkoii_do'};

   % retrieve existing sensor data
   sensorStructOld = get_sensor_struct_old(deployJsonData.glider_sensor, deployJsonDirName, gliderVarNameList);

   sensorStruct.SENSOR = {'OPTODE_DOXY'};
   sensorStruct.SENSOR_MAKER = {'JAC'};
   sensorStruct.SENSOR_MODEL = {'ARO_FT'};
   sensorStruct.SENSOR_SERIAL_NO = repmat({'9999'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_MOUNT = repmat({'MOUNTED_ON_GLIDER'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_ORIENTATION = repmat({''}, size(sensorStruct.SENSOR));

elseif (any(strcmp('sci_oxy4_oxygen', availableParam)))

   egoVarNameList = {'MOLAR_DOXY'};
   gliderVarNameList = {'sci_oxy4_oxygen'};

   % retrieve existing sensor data
   sensorStructOld = get_sensor_struct_old(deployJsonData.glider_sensor, deployJsonDirName, gliderVarNameList);

   sensorStruct.SENSOR = {'OPTODE_DOXY'};
   sensorStruct.SENSOR_MAKER = {'AANDERAA'};
   sensorStruct.SENSOR_MODEL = {'AANDERAA_OPTODE_4330'};
   sensorStruct.SENSOR_SERIAL_NO = repmat({'9999'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_MOUNT = repmat({'MOUNTED_ON_GLIDER'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_ORIENTATION = repmat({''}, size(sensorStruct.SENSOR));

elseif (any(strcmp('sci_oxy3835_oxygen', availableParam)))

   egoVarNameList = {'MOLAR_DOXY'};
   gliderVarNameList = {'sci_oxy3835_oxygen'};

   % retrieve existing sensor data
   sensorStructOld = get_sensor_struct_old(deployJsonData.glider_sensor, deployJsonDirName, gliderVarNameList);

   sensorStruct.SENSOR = {'OPTODE_DOXY'};
   sensorStruct.SENSOR_MAKER = {'AANDERAA'};
   sensorStruct.SENSOR_MODEL = {'AANDERAA_OPTODE_3835'};
   sensorStruct.SENSOR_SERIAL_NO = repmat({'9999'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_MOUNT = repmat({'MOUNTED_ON_GLIDER'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_ORIENTATION = repmat({''}, size(sensorStruct.SENSOR));

elseif (any(strcmp('sci_oxy3835_wphase_oxygen', availableParam)))

   egoVarNameList = {'MOLAR_DOXY'};
   gliderVarNameList = {'sci_oxy3835_wphase_oxygen'};

   % retrieve existing sensor data
   sensorStructOld = get_sensor_struct_old(deployJsonData.glider_sensor, deployJsonDirName, [gliderVarNameList 'sci_oxy3835_oxygen']); % added sci_oxy3835_oxygen to retrieve OPTODE SN from ifm09_depl12_OXYGEN.json

   sensorStruct.SENSOR = {'OPTODE_DOXY'};
   sensorStruct.SENSOR_MAKER = {'AANDERAA'};
   sensorStruct.SENSOR_MODEL = {'AANDERAA_OPTODE_3835'};
   sensorStruct.SENSOR_SERIAL_NO = repmat({'9999'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_MOUNT = repmat({'MOUNTED_ON_GLIDER'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_ORIENTATION = repmat({''}, size(sensorStruct.SENSOR));
end

if (~isempty(gliderVarNameList))

   % set sensor data structure
   paramStructList = repmat(get_param_struct, 1, length(egoVarNameList));
   for idP = 1:length(egoVarNameList)
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
   if (~isempty(sensorStructOld))
      if (~isempty(sensorStructOld.CALIBRATION_COEFFICIENT))
         sensorStruct.CALIBRATION_COEFFICIENT = sensorStructOld.CALIBRATION_COEFFICIENT;
         if (any(strcmp('DOXY', {sensorStructOld.parametersList.ego_variable_name})))
            sensorStruct.PARAMETER{end+1} = 'DOXY';
            sensorStruct.PARAMETER_SENSOR{end+1} = 'OPTODE_DOXY';
            sensorStruct.PARAMETER_DATA_MODE{end+1} = 'R';
            sensorStruct.PARAMETER_UNITS{end+1} = '';
            sensorStruct.PARAMETER_ACCURACY{end+1} = '';
            sensorStruct.PARAMETER_RESOLUTION{end+1} = '';

            idF = find(strcmp('DOXY', {sensorStructOld.parametersList.ego_variable_name}));
            paramStructList(end+1) = get_param_struct;
            paramStructList(end).ego_variable_name = 'DOXY';
            paramStructList(end).derivation_comment = 'Not measured by the glider. Calculated by Coriolis';
            paramStructList(end).processing_id = sensorStructOld.parametersList(idF).processing_id;
         end
         if (any(strcmp('DOXY2', {sensorStructOld.parametersList.ego_variable_name})))
            sensorStruct.PARAMETER{end+1} = 'DOXY2';
            sensorStruct.PARAMETER_SENSOR{end+1} = 'OPTODE_DOXY';
            sensorStruct.PARAMETER_DATA_MODE{end+1} = 'R';
            sensorStruct.PARAMETER_UNITS{end+1} = '';
            sensorStruct.PARAMETER_ACCURACY{end+1} = '';
            sensorStruct.PARAMETER_RESOLUTION{end+1} = '';

            idF = find(strcmp('DOXY2', {sensorStructOld.parametersList.ego_variable_name}));
            paramStructList(end+1) = get_param_struct;
            paramStructList(end).ego_variable_name = 'DOXY2';
            paramStructList(end).derivation_comment = 'Not measured by the glider. Calculated by Coriolis';
            paramStructList(end).processing_id = sensorStructOld.parametersList(idF).processing_id;
         end
         if (any(strcmp('DOXY3', {sensorStructOld.parametersList.ego_variable_name})))
            sensorStruct.PARAMETER{end+1} = 'DOXY3';
            sensorStruct.PARAMETER_SENSOR{end+1} = 'OPTODE_DOXY';
            sensorStruct.PARAMETER_DATA_MODE{end+1} = 'R';
            sensorStruct.PARAMETER_UNITS{end+1} = '';
            sensorStruct.PARAMETER_ACCURACY{end+1} = '';
            sensorStruct.PARAMETER_RESOLUTION{end+1} = '';

            idF = find(strcmp('DOXY3', {sensorStructOld.parametersList.ego_variable_name}));
            paramStructList(end+1) = get_param_struct;
            paramStructList(end).ego_variable_name = 'DOXY3';
            paramStructList(end).derivation_comment = 'Not measured by the glider. Calculated by Coriolis';
            paramStructList(end).processing_id = sensorStructOld.parametersList(idF).processing_id;
         end
      else
         caseStruct = [];
         caseStruct.Case = '201_201_301';
         caseStruct.DoxyCalibRefSalinity = 0;
         sensorStruct.CALIBRATION_COEFFICIENT.OPTODE_DOXY = caseStruct;

         sensorStruct.PARAMETER{end+1} = 'DOXY';
         sensorStruct.PARAMETER_SENSOR{end+1} = 'OPTODE_DOXY';
         sensorStruct.PARAMETER_DATA_MODE{end+1} = 'R';
         sensorStruct.PARAMETER_UNITS{end+1} = '';
         sensorStruct.PARAMETER_ACCURACY{end+1} = '';
         sensorStruct.PARAMETER_RESOLUTION{end+1} = '';

         paramStructList(end+1) = get_param_struct;
         paramStructList(end).ego_variable_name = 'DOXY';
         paramStructList(end).derivation_comment = 'Not measured by the glider. Calculated by Coriolis';
         paramStructList(end).processing_id = '201_201_301';
      end
   else
      caseStruct = [];
      caseStruct.Case = '201_201_301';
      caseStruct.DoxyCalibRefSalinity = 0;
      sensorStruct.CALIBRATION_COEFFICIENT.OPTODE_DOXY = caseStruct;

      sensorStruct.PARAMETER{end+1} = 'DOXY';
      sensorStruct.PARAMETER_SENSOR{end+1} = 'OPTODE_DOXY';
      sensorStruct.PARAMETER_DATA_MODE{end+1} = 'R';
      sensorStruct.PARAMETER_UNITS{end+1} = '';
      sensorStruct.PARAMETER_ACCURACY{end+1} = '';
      sensorStruct.PARAMETER_RESOLUTION{end+1} = '';

      paramStructList(end+1) = get_param_struct;
      paramStructList(end).ego_variable_name = 'DOXY';
      paramStructList(end).derivation_comment = 'Not measured by the glider. Calculated by Coriolis';
      paramStructList(end).processing_id = '201_201_301';
   end

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
% FLNTU

sensorStruct = get_sensor_struct;
sensorStructOld = [];
gliderVarNameList = [];
if (any(strcmp('sci_flntu_chlor_sig', availableParam)) && ...
      any(strcmp('sci_flntu_chlor_units', availableParam)) && ...
      any(strcmp('sci_flntu_temp', availableParam)) && ...
      any(strcmp('sci_flntu_turb_sig', availableParam)) && ...
      any(strcmp('sci_flntu_turb_units', availableParam)))

   egoVarNameList = {'FLUORESCENCE_CHLA' 'TEMP_CPU_CHLA' 'CHLA' 'SIDE_SCATTERING_TURBIDITY' 'TURBIDITY'};
   gliderVarNameList = {'sci_flntu_chlor_sig' 'sci_flntu_temp' 'sci_flntu_chlor_units' 'sci_flntu_turb_sig' 'sci_flntu_turb_units'};

   % retrieve existing sensor data
   sensorStructOld = get_sensor_struct_old(deployJsonData.glider_sensor, deployJsonDirName, gliderVarNameList);

   sensorStruct.SENSOR = {'FLUOROMETER_CHLA' 'BACKSCATTERINGMETER_TURBIDITY'};
   sensorStruct.SENSOR_MAKER = {'WETLABS' 'WETLABS'};
   sensorStruct.SENSOR_MODEL = {'ECO_FLNTU' 'ECO_FLNTU'};
   sensorStruct.SENSOR_SERIAL_NO = repmat({'9999'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_MOUNT = repmat({'MOUNTED_ON_GLIDER'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_ORIENTATION = repmat({''}, size(sensorStruct.SENSOR));

   sensorStruct.PARAMETER = {'FLUORESCENCE_CHLA' 'TEMP_CPU_CHLA' 'CHLA' 'SIDE_SCATTERING_TURBIDITY' 'TURBIDITY'};
   sensorStruct.PARAMETER_SENSOR = {'FLUOROMETER_CHLA' 'FLUOROMETER_CHLA' 'FLUOROMETER_CHLA' 'BACKSCATTERINGMETER_TURBIDITY' 'BACKSCATTERINGMETER_TURBIDITY'};
   sensorStruct.PARAMETER_DATA_MODE = repmat({'R'}, 1, length(sensorStruct.PARAMETER));
   sensorStruct.PARAMETER_UNITS = repmat({''}, 1, length(sensorStruct.PARAMETER));
   sensorStruct.PARAMETER_ACCURACY = repmat({''}, 1, length(sensorStruct.PARAMETER));
   sensorStruct.PARAMETER_RESOLUTION = repmat({''}, 1, length(sensorStruct.PARAMETER));

elseif (any(strcmp('sci_flntu_chlor_sig', availableParam)) && ...
      any(strcmp('sci_flntu_chlor_units', availableParam)) && ...
      any(strcmp('sci_flntu_temp', availableParam)) && ...
      any(strcmp('sci_flntu_turb_sig', availableParam)))

   egoVarNameList = {'FLUORESCENCE_CHLA' 'TEMP_CPU_CHLA' 'CHLA' 'SIDE_SCATTERING_TURBIDITY'};
   gliderVarNameList = {'sci_flntu_chlor_sig' 'sci_flntu_temp' 'sci_flntu_chlor_units' 'sci_flntu_turb_sig'};

   % retrieve existing sensor data
   sensorStructOld = get_sensor_struct_old(deployJsonData.glider_sensor, deployJsonDirName, gliderVarNameList);

   sensorStruct.SENSOR = {'FLUOROMETER_CHLA' 'BACKSCATTERINGMETER_TURBIDITY'};
   sensorStruct.SENSOR_MAKER = {'WETLABS' 'WETLABS'};
   sensorStruct.SENSOR_MODEL = {'ECO_FLNTU' 'ECO_FLNTU'};
   sensorStruct.SENSOR_SERIAL_NO = repmat({'9999'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_MOUNT = repmat({'MOUNTED_ON_GLIDER'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_ORIENTATION = repmat({''}, size(sensorStruct.SENSOR));

   sensorStruct.PARAMETER = {'FLUORESCENCE_CHLA' 'TEMP_CPU_CHLA' 'CHLA' 'SIDE_SCATTERING_TURBIDITY'};
   sensorStruct.PARAMETER_SENSOR = {'FLUOROMETER_CHLA' 'FLUOROMETER_CHLA' 'FLUOROMETER_CHLA' 'BACKSCATTERINGMETER_TURBIDITY'};
   sensorStruct.PARAMETER_DATA_MODE = repmat({'R'}, 1, length(sensorStruct.PARAMETER));
   sensorStruct.PARAMETER_UNITS = repmat({''}, 1, length(sensorStruct.PARAMETER));
   sensorStruct.PARAMETER_ACCURACY = repmat({''}, 1, length(sensorStruct.PARAMETER));
   sensorStruct.PARAMETER_RESOLUTION = repmat({''}, 1, length(sensorStruct.PARAMETER));

elseif (any(strcmp('sci_flntu_chlor_sig', availableParam)) && ...
      any(strcmp('sci_flntu_chlor_units', availableParam)) && ...
      any(strcmp('sci_flntu_turb_sig', availableParam)) && ...
      any(strcmp('sci_flntu_turb_units', availableParam)))

   egoVarNameList = {'FLUORESCENCE_CHLA' 'CHLA' 'SIDE_SCATTERING_TURBIDITY' 'TURBIDITY'};
   gliderVarNameList = {'sci_flntu_chlor_sig' 'sci_flntu_chlor_units' 'sci_flntu_turb_sig' 'sci_flntu_turb_units'};

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

elseif (any(strcmp('sci_flntu_chlor_units', availableParam)) && ...
      any(strcmp('sci_flntu_turb_units', availableParam)))

   egoVarNameList = {'CHLA' 'TURBIDITY'};
   gliderVarNameList = {'sci_flntu_chlor_units' 'sci_flntu_turb_units'};

   % retrieve existing sensor data
   sensorStructOld = get_sensor_struct_old(deployJsonData.glider_sensor, deployJsonDirName, gliderVarNameList);

   sensorStruct.SENSOR = {'FLUOROMETER_CHLA' 'BACKSCATTERINGMETER_TURBIDITY'};
   sensorStruct.SENSOR_MAKER = {'WETLABS' 'WETLABS'};
   sensorStruct.SENSOR_MODEL = {'ECO_FLNTU' 'ECO_FLNTU'};
   sensorStruct.SENSOR_SERIAL_NO = repmat({'9999'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_MOUNT = repmat({'MOUNTED_ON_GLIDER'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_ORIENTATION = repmat({''}, size(sensorStruct.SENSOR));

   sensorStruct.PARAMETER = {'CHLA' 'TURBIDITY'};
   sensorStruct.PARAMETER_SENSOR = {'FLUOROMETER_CHLA' 'BACKSCATTERINGMETER_TURBIDITY'};
   sensorStruct.PARAMETER_DATA_MODE = repmat({'R'}, 1, length(sensorStruct.PARAMETER));
   sensorStruct.PARAMETER_UNITS = repmat({''}, 1, length(sensorStruct.PARAMETER));
   sensorStruct.PARAMETER_ACCURACY = repmat({''}, 1, length(sensorStruct.PARAMETER));
   sensorStruct.PARAMETER_RESOLUTION = repmat({''}, 1, length(sensorStruct.PARAMETER));

elseif (any(strcmp('gld_dup_sci_flntu_chlor_units', availableParam)) && ...
      any(strcmp('gld_dup_sci_flntu_turb_units', availableParam)))

   egoVarNameList = {'CHLA' 'TURBIDITY'};
   gliderVarNameList = {'gld_dup_sci_flntu_chlor_units' 'gld_dup_sci_flntu_turb_units'};

   % retrieve existing sensor data
   sensorStructOld = get_sensor_struct_old(deployJsonData.glider_sensor, deployJsonDirName, gliderVarNameList);

   sensorStruct.SENSOR = {'FLUOROMETER_CHLA' 'BACKSCATTERINGMETER_TURBIDITY'};
   sensorStruct.SENSOR_MAKER = {'WETLABS' 'WETLABS'};
   sensorStruct.SENSOR_MODEL = {'ECO_FLNTU' 'ECO_FLNTU'};
   sensorStruct.SENSOR_SERIAL_NO = repmat({'9999'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_MOUNT = repmat({'MOUNTED_ON_GLIDER'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_ORIENTATION = repmat({''}, size(sensorStruct.SENSOR));

   sensorStruct.PARAMETER = {'CHLA' 'TURBIDITY'};
   sensorStruct.PARAMETER_SENSOR = {'FLUOROMETER_CHLA' 'BACKSCATTERINGMETER_TURBIDITY'};
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
if (any(strcmp('sci_flbbcd_chlor_sig', availableParam)) && ...
      any(strcmp('sci_flbbcd_chlor_units', availableParam)) && ...
      any(strcmp('sci_flbbcd_bb_sig', availableParam)) && ...
      any(strcmp('sci_flbbcd_bb_units', availableParam)) && ...
      any(strcmp('sci_flbbcd_cdom_sig', availableParam)) && ...
      any(strcmp('sci_flbbcd_cdom_units', availableParam)))

   egoVarNameList = {'FLUORESCENCE_CHLA' 'CHLA' 'BETA_BACKSCATTERING700' 'BBP700' 'FLUORESCENCE_CDOM' 'CDOM'};
   gliderVarNameList = {'sci_flbbcd_chlor_sig' 'sci_flbbcd_chlor_units' 'sci_flbbcd_bb_sig' 'sci_flbbcd_bb_units' 'sci_flbbcd_cdom_sig' 'sci_flbbcd_cdom_units'};

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

elseif (any(strcmp('sci_flbbcd_chlor_units', availableParam)) && ...
      any(strcmp('sci_flbbcd_bb_units', availableParam)) && ...
      any(strcmp('sci_flbbcd_cdom_units', availableParam)))

   egoVarNameList = {'CHLA' 'BBP700' 'CDOM'};
   gliderVarNameList = {'sci_flbbcd_chlor_units' 'sci_flbbcd_bb_units' 'sci_flbbcd_cdom_units'};

   % retrieve existing sensor data
   sensorStructOld = get_sensor_struct_old(deployJsonData.glider_sensor, deployJsonDirName, [gliderVarNameList 'sci_flntu_chlor_units']); % added sci_flntu_chlor_units to retrieve ECO_FLBBCD SN from ifm13_depl06_FLUOROMETER.json

   sensorStruct.SENSOR = {'FLUOROMETER_CHLA' 'BACKSCATTERINGMETER_BBP700' 'FLUOROMETER_CDOM'};
   sensorStruct.SENSOR_MAKER = {'WETLABS' 'WETLABS' 'WETLABS'};
   sensorStruct.SENSOR_MODEL = {'ECO_FLBBCD' 'ECO_FLBBCD' 'ECO_FLBBCD'};
   sensorStruct.SENSOR_SERIAL_NO = repmat({'9999'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_MOUNT = repmat({'MOUNTED_ON_GLIDER'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_ORIENTATION = repmat({''}, size(sensorStruct.SENSOR));

   sensorStruct.PARAMETER = {'CHLA' 'BBP700' 'CDOM'};
   sensorStruct.PARAMETER_SENSOR = {'FLUOROMETER_CHLA' 'BACKSCATTERINGMETER_BBP700' 'FLUOROMETER_CDOM'};
   sensorStruct.PARAMETER_DATA_MODE = repmat({'R'}, 1, length(sensorStruct.PARAMETER));
   sensorStruct.PARAMETER_UNITS = repmat({''}, 1, length(sensorStruct.PARAMETER));
   sensorStruct.PARAMETER_ACCURACY = repmat({''}, 1, length(sensorStruct.PARAMETER));
   sensorStruct.PARAMETER_RESOLUTION = repmat({''}, 1, length(sensorStruct.PARAMETER));

elseif (any(strcmp('sci_flbbcd_chlor_units', availableParam)) && ...
      any(strcmp('sci_flbbcd_cdom_units', availableParam)))

   egoVarNameList = {'CHLA' 'CDOM'};
   gliderVarNameList = {'sci_flbbcd_chlor_units' 'sci_flbbcd_cdom_units'};

   % retrieve existing sensor data
   sensorStructOld = get_sensor_struct_old(deployJsonData.glider_sensor, deployJsonDirName, gliderVarNameList);

   sensorStruct.SENSOR = {'FLUOROMETER_CHLA' 'FLUOROMETER_CDOM'};
   sensorStruct.SENSOR_MAKER = {'WETLABS' 'WETLABS'};
   sensorStruct.SENSOR_MODEL = {'ECO_FLBBCD' 'ECO_FLBBCD'};
   sensorStruct.SENSOR_SERIAL_NO = repmat({'9999'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_MOUNT = repmat({'MOUNTED_ON_GLIDER'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_ORIENTATION = repmat({''}, size(sensorStruct.SENSOR));

   sensorStruct.PARAMETER = {'CHLA' 'CDOM'};
   sensorStruct.PARAMETER_SENSOR = {'FLUOROMETER_CHLA' 'FLUOROMETER_CDOM'};
   sensorStruct.PARAMETER_DATA_MODE = repmat({'R'}, 1, length(sensorStruct.PARAMETER));
   sensorStruct.PARAMETER_UNITS = repmat({''}, 1, length(sensorStruct.PARAMETER));
   sensorStruct.PARAMETER_ACCURACY = repmat({''}, 1, length(sensorStruct.PARAMETER));
   sensorStruct.PARAMETER_RESOLUTION = repmat({''}, 1, length(sensorStruct.PARAMETER));

elseif (any(strcmp('sci_flbbcd_chlor_units', availableParam)) && ...
      any(strcmp('sci_flbbcd_bb_units', availableParam)))

   egoVarNameList = {'CHLA' 'BBP700'};
   gliderVarNameList = {'sci_flbbcd_chlor_units' 'sci_flbbcd_bb_units'};

   % retrieve existing sensor data
   sensorStructOld = get_sensor_struct_old(deployJsonData.glider_sensor, deployJsonDirName, gliderVarNameList);

   sensorStruct.SENSOR = {'FLUOROMETER_CHLA' 'BACKSCATTERINGMETER_BBP700'};
   sensorStruct.SENSOR_MAKER = {'WETLABS' 'WETLABS'};
   sensorStruct.SENSOR_MODEL = {'ECO_FLBBCD' 'ECO_FLBBCD'};
   sensorStruct.SENSOR_SERIAL_NO = repmat({'9999'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_MOUNT = repmat({'MOUNTED_ON_GLIDER'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_ORIENTATION = repmat({''}, size(sensorStruct.SENSOR));

   sensorStruct.PARAMETER = {'CHLA' 'BBP700'};
   sensorStruct.PARAMETER_SENSOR = {'FLUOROMETER_CHLA' 'BACKSCATTERINGMETER_BBP700'};
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
% BB2FL (s)

sensorStruct = get_sensor_struct;
sensorStructOld = [];
gliderVarNameListBb2fl = [];
gliderVarNameList = [];
if (any(strcmp('sci_bb2fls_cdom_scaled', availableParam)) && ...
      any(strcmp('sci_bb2fls_b660_scaled', availableParam)) && ...
      any(strcmp('sci_bb2fls_b880_scaled', availableParam)))

   egoVarNameList = {'CDOM' 'BBP660' 'BBP880'};
   gliderVarNameList = {'sci_bb2fls_cdom_scaled' 'sci_bb2fls_b660_scaled' 'sci_bb2fls_b880_scaled'};
   gliderVarNameListBb2fl = [gliderVarNameListBb2fl gliderVarNameList];

   % retrieve existing sensor data
   sensorStructOld = get_sensor_struct_old(deployJsonData.glider_sensor, deployJsonDirName, gliderVarNameList);

   sensorStruct.SENSOR = {'FLUOROMETER_CDOM' 'BACKSCATTERINGMETER_BBP660' 'BACKSCATTERINGMETER_BBP880'};
   sensorStruct.SENSOR_MAKER = {'WETLABS' 'WETLABS' 'WETLABS'};
   sensorStruct.SENSOR_MODEL = {'ECO_FLBB2' 'ECO_FLBB2' 'ECO_FLBB2'};
   sensorStruct.SENSOR_SERIAL_NO = repmat({'9999'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_MOUNT = repmat({'MOUNTED_ON_GLIDER'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_ORIENTATION = repmat({''}, size(sensorStruct.SENSOR));

   sensorStruct.PARAMETER = {'CDOM' 'BBP660' 'BBP880'};
   sensorStruct.PARAMETER_SENSOR = {'FLUOROMETER_CDOM' 'BACKSCATTERINGMETER_BBP660' 'BACKSCATTERINGMETER_BBP880'};
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
   sensorStruct = update_sensor_data(sensorStruct, sensorStructOld, a_deploymentDirName, 'FLBB2_s', a_csvFid);

   % generate sensor json file
   outputFileName = [a_deploymentDirName '_ECO_FLBB2_s_' sensorStruct.SENSOR_SERIAL_NO{1} '.json'];
   outputFilePathName = [outputDirName outputFileName];
   sensorFileNameList{end+1} = outputFileName;

   ok = write_json_sensor_file(outputFilePathName, sensorStruct);
   if (ok == 0)
      fprintf('ERROR: Error while generating sensor JSON file: %s\n', outputFilePathName);
   end
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% BB2FL (sv2)

sensorStruct = get_sensor_struct;
sensorStructOld = [];
gliderVarNameList = [];
if (any(strcmp('sci_bb2flsv2_chl_scaled', availableParam)) && ...
      any(strcmp('sci_bb2flsv2_b470_scaled', availableParam)) && ...
      any(strcmp('sci_bb2flsv2_b532_scaled', availableParam)))

   egoVarNameList = {'CHLA' 'BBP470' 'BBP532'};
   gliderVarNameList = {'sci_bb2flsv2_chl_scaled' 'sci_bb2flsv2_b470_scaled' 'sci_bb2flsv2_b532_scaled'};
   gliderVarNameListBb2fl = [gliderVarNameListBb2fl gliderVarNameList];

   % retrieve existing sensor data
   sensorStructOld = get_sensor_struct_old(deployJsonData.glider_sensor, deployJsonDirName, gliderVarNameList);

   sensorStruct.SENSOR = {'FLUOROMETER_CHLA' 'BACKSCATTERINGMETER_BBP470' 'BACKSCATTERINGMETER_BBP532'};
   sensorStruct.SENSOR_MAKER = {'WETLABS' 'WETLABS' 'WETLABS'};
   sensorStruct.SENSOR_MODEL = {'ECO_FLBB2' 'ECO_FLBB2' 'ECO_FLBB2'};
   sensorStruct.SENSOR_SERIAL_NO = repmat({'9999'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_MOUNT = repmat({'MOUNTED_ON_GLIDER'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_ORIENTATION = repmat({''}, size(sensorStruct.SENSOR));

   sensorStruct.PARAMETER = {'CHLA' 'BBP470' 'BBP532'};
   sensorStruct.PARAMETER_SENSOR = {'FLUOROMETER_CHLA' 'BACKSCATTERINGMETER_BBP470' 'BACKSCATTERINGMETER_BBP532'};
   sensorStruct.PARAMETER_DATA_MODE = repmat({'R'}, 1, length(sensorStruct.PARAMETER));
   sensorStruct.PARAMETER_UNITS = repmat({''}, 1, length(sensorStruct.PARAMETER));
   sensorStruct.PARAMETER_ACCURACY = repmat({''}, 1, length(sensorStruct.PARAMETER));
   sensorStruct.PARAMETER_RESOLUTION = repmat({''}, 1, length(sensorStruct.PARAMETER));

elseif (any(strcmp('sci_bb2flsv2_chl_scaled', availableParam)))

   egoVarNameList = {'CHLA'};
   gliderVarNameList = {'sci_bb2flsv2_chl_scaled'};
   gliderVarNameListBb2fl = [gliderVarNameListBb2fl gliderVarNameList];

   % retrieve existing sensor data
   sensorStructOld = get_sensor_struct_old(deployJsonData.glider_sensor, deployJsonDirName, gliderVarNameList);

   sensorStruct.SENSOR = {'FLUOROMETER_CHLA'};
   sensorStruct.SENSOR_MAKER = {'WETLABS'};
   sensorStruct.SENSOR_MODEL = {'ECO_FLBB2'};
   sensorStruct.SENSOR_SERIAL_NO = repmat({'9999'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_MOUNT = repmat({'MOUNTED_ON_GLIDER'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_ORIENTATION = repmat({''}, size(sensorStruct.SENSOR));

   sensorStruct.PARAMETER = {'CHLA'};
   sensorStruct.PARAMETER_SENSOR = {'FLUOROMETER_CHLA'};
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
   sensorStruct = update_sensor_data(sensorStruct, sensorStructOld, a_deploymentDirName, 'FLBB2_sv2', a_csvFid);

   % generate sensor json file
   outputFileName = [a_deploymentDirName '_ECO_FLBB2_sv2_' sensorStruct.SENSOR_SERIAL_NO{1} '.json'];
   outputFilePathName = [outputDirName outputFileName];
   sensorFileNameList{end+1} = outputFileName;

   ok = write_json_sensor_file(outputFilePathName, sensorStruct);
   if (ok == 0)
      fprintf('ERROR: Error while generating sensor JSON file: %s\n', outputFilePathName);
   end
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% BB2FL (sv3)

sensorStruct = get_sensor_struct;
sensorStructOld = [];
gliderVarNameList = [];
if (any(strcmp('sci_bb2flsv3_pe_scaled', availableParam)) && ...
      any(strcmp('sci_bb2flsv3_b715_scaled', availableParam)) && ...
      any(strcmp('sci_bb2flsv3_b880_scaled', availableParam)))

   egoVarNameList = {'PE' 'BBP715' 'BBP880'};
   gliderVarNameList = {'sci_bb2flsv3_pe_scaled' 'sci_bb2flsv3_b715_scaled' 'sci_bb2flsv3_b880_scaled'};
   gliderVarNameListBb2fl = [gliderVarNameListBb2fl gliderVarNameList];

   % retrieve existing sensor data
   sensorStructOld = get_sensor_struct_old(deployJsonData.glider_sensor, deployJsonDirName, gliderVarNameList);

   sensorStruct.SENSOR = {'FLUOROMETER_PE' 'BACKSCATTERINGMETER_BBP715' 'BACKSCATTERINGMETER_BBP880'};
   sensorStruct.SENSOR_MAKER = {'WETLABS' 'WETLABS' 'WETLABS'};
   sensorStruct.SENSOR_MODEL = {'ECO_FLBB2' 'ECO_FLBB2' 'ECO_FLBB2'};
   sensorStruct.SENSOR_SERIAL_NO = repmat({'9999'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_MOUNT = repmat({'MOUNTED_ON_GLIDER'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_ORIENTATION = repmat({''}, size(sensorStruct.SENSOR));

   sensorStruct.PARAMETER = {'PE' 'BBP715' 'BBP880'};
   sensorStruct.PARAMETER_SENSOR = {'FLUOROMETER_PE' 'BACKSCATTERINGMETER_BBP715' 'BACKSCATTERINGMETER_BBP880'};
   sensorStruct.PARAMETER_DATA_MODE = repmat({'R'}, 1, length(sensorStruct.PARAMETER));
   sensorStruct.PARAMETER_UNITS = repmat({''}, 1, length(sensorStruct.PARAMETER));
   sensorStruct.PARAMETER_ACCURACY = repmat({''}, 1, length(sensorStruct.PARAMETER));
   sensorStruct.PARAMETER_RESOLUTION = repmat({''}, 1, length(sensorStruct.PARAMETER));

elseif (any(strcmp('sci_bb2flsv3_b715_scaled', availableParam)) && ...
      any(strcmp('sci_bb2flsv3_b880_scaled', availableParam)))

   egoVarNameList = {'BBP715' 'BBP880'};
   gliderVarNameList = {'sci_bb2flsv3_b715_scaled' 'sci_bb2flsv3_b880_scaled'};
   gliderVarNameListBb2fl = [gliderVarNameListBb2fl gliderVarNameList];

   % retrieve existing sensor data
   sensorStructOld = get_sensor_struct_old(deployJsonData.glider_sensor, deployJsonDirName, gliderVarNameList);

   sensorStruct.SENSOR = {'BACKSCATTERINGMETER_BBP715' 'BACKSCATTERINGMETER_BBP880'};
   sensorStruct.SENSOR_MAKER = {'WETLABS' 'WETLABS'};
   sensorStruct.SENSOR_MODEL = {'ECO_FLBB2' 'ECO_FLBB2'};
   sensorStruct.SENSOR_SERIAL_NO = repmat({'9999'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_MOUNT = repmat({'MOUNTED_ON_GLIDER'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_ORIENTATION = repmat({''}, size(sensorStruct.SENSOR));

   sensorStruct.PARAMETER = {'BBP715' 'BBP880'};
   sensorStruct.PARAMETER_SENSOR = {'BACKSCATTERINGMETER_BBP715' 'BACKSCATTERINGMETER_BBP880'};
   sensorStruct.PARAMETER_DATA_MODE = repmat({'R'}, 1, length(sensorStruct.PARAMETER));
   sensorStruct.PARAMETER_UNITS = repmat({''}, 1, length(sensorStruct.PARAMETER));
   sensorStruct.PARAMETER_ACCURACY = repmat({''}, 1, length(sensorStruct.PARAMETER));
   sensorStruct.PARAMETER_RESOLUTION = repmat({''}, 1, length(sensorStruct.PARAMETER));

elseif (any(strcmp('sci_bb2flsv3_pe_scaled', availableParam)) && ...
      any(strcmp('sci_bb2flsv3_b880_scaled', availableParam)))

   egoVarNameList = {'PE' 'BBP880'};
   gliderVarNameList = {'sci_bb2flsv3_pe_scaled' 'sci_bb2flsv3_b880_scaled'};
   gliderVarNameListBb2fl = [gliderVarNameListBb2fl gliderVarNameList];

   % retrieve existing sensor data
   sensorStructOld = get_sensor_struct_old(deployJsonData.glider_sensor, deployJsonDirName, gliderVarNameList);

   sensorStruct.SENSOR = {'FLUOROMETER_PE' 'BACKSCATTERINGMETER_BBP880'};
   sensorStruct.SENSOR_MAKER = {'WETLABS' 'WETLABS'};
   sensorStruct.SENSOR_MODEL = {'ECO_FLBB2' 'ECO_FLBB2'};
   sensorStruct.SENSOR_SERIAL_NO = repmat({'9999'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_MOUNT = repmat({'MOUNTED_ON_GLIDER'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_ORIENTATION = repmat({''}, size(sensorStruct.SENSOR));

   sensorStruct.PARAMETER = {'PE' 'BBP880'};
   sensorStruct.PARAMETER_SENSOR = {'FLUOROMETER_PE' 'BACKSCATTERINGMETER_BBP880'};
   sensorStruct.PARAMETER_DATA_MODE = repmat({'R'}, 1, length(sensorStruct.PARAMETER));
   sensorStruct.PARAMETER_UNITS = repmat({''}, 1, length(sensorStruct.PARAMETER));
   sensorStruct.PARAMETER_ACCURACY = repmat({''}, 1, length(sensorStruct.PARAMETER));
   sensorStruct.PARAMETER_RESOLUTION = repmat({''}, 1, length(sensorStruct.PARAMETER));

elseif (any(strcmp('sci_bb2flsv3_b715_scaled', availableParam)))

   egoVarNameList = {'BBP715'};
   gliderVarNameList = {'sci_bb2flsv3_b715_scaled'};
   gliderVarNameListBb2fl = [gliderVarNameListBb2fl gliderVarNameList];

   % retrieve existing sensor data
   sensorStructOld = get_sensor_struct_old(deployJsonData.glider_sensor, deployJsonDirName, gliderVarNameList);

   sensorStruct.SENSOR = {'BACKSCATTERINGMETER_BBP715'};
   sensorStruct.SENSOR_MAKER = {'WETLABS'};
   sensorStruct.SENSOR_MODEL = {'ECO_FLBB2'};
   sensorStruct.SENSOR_SERIAL_NO = repmat({'9999'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_MOUNT = repmat({'MOUNTED_ON_GLIDER'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_ORIENTATION = repmat({''}, size(sensorStruct.SENSOR));

   sensorStruct.PARAMETER = {'BBP715'};
   sensorStruct.PARAMETER_SENSOR = {'BACKSCATTERINGMETER_BBP715'};
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
   sensorStruct = update_sensor_data(sensorStruct, sensorStructOld, a_deploymentDirName, 'FLBB2_sv3', a_csvFid);

   % generate sensor json file
   outputFileName = [a_deploymentDirName '_ECO_FLBB2_sv3_' sensorStruct.SENSOR_SERIAL_NO{1} '.json'];
   outputFilePathName = [outputDirName outputFileName];
   sensorFileNameList{end+1} = outputFileName;

   ok = write_json_sensor_file(outputFilePathName, sensorStruct);
   if (ok == 0)
      fprintf('ERROR: Error while generating sensor JSON file: %s\n', outputFilePathName);
   end
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% BB2FL (sv4)

sensorStruct = get_sensor_struct;
sensorStructOld = [];
gliderVarNameList = [];
if (any(strcmp('sci_bb2flsv4_chl_scaled', availableParam)) && ...
      any(strcmp('sci_bb2flsv4_b412_scaled', availableParam)) && ...
      any(strcmp('sci_bb2flsv4_b470_scaled', availableParam)))

   egoVarNameList = {'CHLA' 'BBP412' 'BBP470'};
   gliderVarNameList = {'sci_bb2flsv4_chl_scaled' 'sci_bb2flsv4_b412_scaled' 'sci_bb2flsv4_b470_scaled'};
   gliderVarNameListBb2fl = [gliderVarNameListBb2fl gliderVarNameList];

   % retrieve existing sensor data
   sensorStructOld = get_sensor_struct_old(deployJsonData.glider_sensor, deployJsonDirName, gliderVarNameList);

   sensorStruct.SENSOR = {'FLUOROMETER_CHLA' 'BACKSCATTERINGMETER_BBP412' 'BACKSCATTERINGMETER_BBP470'};
   sensorStruct.SENSOR_MAKER = {'WETLABS' 'WETLABS' 'WETLABS'};
   sensorStruct.SENSOR_MODEL = {'ECO_FLBB2' 'ECO_FLBB2' 'ECO_FLBB2'};
   sensorStruct.SENSOR_SERIAL_NO = repmat({'9999'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_MOUNT = repmat({'MOUNTED_ON_GLIDER'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_ORIENTATION = repmat({''}, size(sensorStruct.SENSOR));

   sensorStruct.PARAMETER = {'CHLA' 'BBP412' 'BBP470'};
   sensorStruct.PARAMETER_SENSOR = {'FLUOROMETER_CHLA' 'BACKSCATTERINGMETER_BBP412' 'BACKSCATTERINGMETER_BBP470'};
   sensorStruct.PARAMETER_DATA_MODE = repmat({'R'}, 1, length(sensorStruct.PARAMETER));
   sensorStruct.PARAMETER_UNITS = repmat({''}, 1, length(sensorStruct.PARAMETER));
   sensorStruct.PARAMETER_ACCURACY = repmat({''}, 1, length(sensorStruct.PARAMETER));
   sensorStruct.PARAMETER_RESOLUTION = repmat({''}, 1, length(sensorStruct.PARAMETER));

elseif (any(strcmp('sci_bb2flsv4_chl_scaled', availableParam)))

   egoVarNameList = {'CHLA'};
   gliderVarNameList = {'sci_bb2flsv4_chl_scaled'};
   gliderVarNameListBb2fl = [gliderVarNameListBb2fl gliderVarNameList];

   % retrieve existing sensor data
   sensorStructOld = get_sensor_struct_old(deployJsonData.glider_sensor, deployJsonDirName, gliderVarNameList);

   sensorStruct.SENSOR = {'FLUOROMETER_CHLA'};
   sensorStruct.SENSOR_MAKER = {'WETLABS'};
   sensorStruct.SENSOR_MODEL = {'ECO_FLBB2'};
   sensorStruct.SENSOR_SERIAL_NO = repmat({'9999'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_MOUNT = repmat({'MOUNTED_ON_GLIDER'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_ORIENTATION = repmat({''}, size(sensorStruct.SENSOR));

   sensorStruct.PARAMETER = {'CHLA'};
   sensorStruct.PARAMETER_SENSOR = {'FLUOROMETER_CHLA'};
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
   sensorStruct = update_sensor_data(sensorStruct, sensorStructOld, a_deploymentDirName, 'FLBB2_sv4', a_csvFid);

   % generate sensor json file
   outputFileName = [a_deploymentDirName '_ECO_FLBB2_sv4_' sensorStruct.SENSOR_SERIAL_NO{1} '.json'];
   outputFilePathName = [outputDirName outputFileName];
   sensorFileNameList{end+1} = outputFileName;

   ok = write_json_sensor_file(outputFilePathName, sensorStruct);
   if (ok == 0)
      fprintf('ERROR: Error while generating sensor JSON file: %s\n', outputFilePathName);
   end
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% BB2FL (sv5)

sensorStruct = get_sensor_struct;
sensorStructOld = [];
gliderVarNameList = [];
if (any(strcmp('sci_bb2flsv5_cdom_scaled', availableParam)) && ...
      any(strcmp('sci_bb2flsv5_b532_scaled', availableParam)) && ...
      any(strcmp('sci_bb2flsv5_b660_scaled', availableParam)))

   egoVarNameList = {'CDOM' 'BBP532' 'BBP660'};
   gliderVarNameList = {'sci_bb2flsv5_cdom_scaled' 'sci_bb2flsv5_b532_scaled' 'sci_bb2flsv5_b660_scaled'};
   gliderVarNameListBb2fl = [gliderVarNameListBb2fl gliderVarNameList];

   % retrieve existing sensor data
   sensorStructOld = get_sensor_struct_old(deployJsonData.glider_sensor, deployJsonDirName, gliderVarNameList);

   sensorStruct.SENSOR = {'FLUOROMETER_CDOM' 'BACKSCATTERINGMETER_BBP532' 'BACKSCATTERINGMETER_BBP660'};
   sensorStruct.SENSOR_MAKER = {'WETLABS' 'WETLABS' 'WETLABS'};
   sensorStruct.SENSOR_MODEL = {'ECO_FLBB2' 'ECO_FLBB2' 'ECO_FLBB2'};
   sensorStruct.SENSOR_SERIAL_NO = repmat({'9999'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_MOUNT = repmat({'MOUNTED_ON_GLIDER'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_ORIENTATION = repmat({''}, size(sensorStruct.SENSOR));

   sensorStruct.PARAMETER = {'CDOM' 'BBP532' 'BBP660'};
   sensorStruct.PARAMETER_SENSOR = {'FLUOROMETER_CDOM' 'BACKSCATTERINGMETER_BBP532' 'BACKSCATTERINGMETER_BBP660'};
   sensorStruct.PARAMETER_DATA_MODE = repmat({'R'}, 1, length(sensorStruct.PARAMETER));
   sensorStruct.PARAMETER_UNITS = repmat({''}, 1, length(sensorStruct.PARAMETER));
   sensorStruct.PARAMETER_ACCURACY = repmat({''}, 1, length(sensorStruct.PARAMETER));
   sensorStruct.PARAMETER_RESOLUTION = repmat({''}, 1, length(sensorStruct.PARAMETER));

elseif (any(strcmp('sci_bb2flsv5_cdom_scaled', availableParam)))

   egoVarNameList = {'CDOM'};
   gliderVarNameList = {'sci_bb2flsv5_cdom_scaled'};
   gliderVarNameListBb2fl = [gliderVarNameListBb2fl gliderVarNameList];

   % retrieve existing sensor data
   sensorStructOld = get_sensor_struct_old(deployJsonData.glider_sensor, deployJsonDirName, gliderVarNameList);

   sensorStruct.SENSOR = {'FLUOROMETER_CDOM'};
   sensorStruct.SENSOR_MAKER = {'WETLABS'};
   sensorStruct.SENSOR_MODEL = {'ECO_FLBB2'};
   sensorStruct.SENSOR_SERIAL_NO = repmat({'9999'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_MOUNT = repmat({'MOUNTED_ON_GLIDER'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_ORIENTATION = repmat({''}, size(sensorStruct.SENSOR));

   sensorStruct.PARAMETER = {'CDOM'};
   sensorStruct.PARAMETER_SENSOR = {'FLUOROMETER_CDOM'};
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
   sensorStruct = update_sensor_data(sensorStruct, sensorStructOld, a_deploymentDirName, 'FLBB2_sv5', a_csvFid);

   % generate sensor json file
   outputFileName = [a_deploymentDirName '_ECO_FLBB2_sv5_' sensorStruct.SENSOR_SERIAL_NO{1} '.json'];
   outputFilePathName = [outputDirName outputFileName];
   sensorFileNameList{end+1} = outputFileName;

   ok = write_json_sensor_file(outputFilePathName, sensorStruct);
   if (ok == 0)
      fprintf('ERROR: Error while generating sensor JSON file: %s\n', outputFilePathName);
   end
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% BB2FL (sv6)

sensorStruct = get_sensor_struct;
sensorStructOld = [];
gliderVarNameList = [];
if (any(strcmp('sci_bb2flsv6_cdom_scaled', availableParam)) && ...
      any(strcmp('sci_bb2flsv6_b532_scaled', availableParam)) && ...
      any(strcmp('sci_bb2flsv6_b880_scaled', availableParam)))

   egoVarNameList = {'CDOM' 'BBP532' 'BBP880'};
   gliderVarNameList = {'sci_bb2flsv6_cdom_scaled' 'sci_bb2flsv6_b532_scaled' 'sci_bb2flsv6_b880_scaled'};
   gliderVarNameListBb2fl = [gliderVarNameListBb2fl gliderVarNameList];

   % retrieve existing sensor data
   sensorStructOld = get_sensor_struct_old(deployJsonData.glider_sensor, deployJsonDirName, gliderVarNameList);

   sensorStruct.SENSOR = {'FLUOROMETER_CDOM' 'BACKSCATTERINGMETER_BBP532' 'BACKSCATTERINGMETER_BBP880'};
   sensorStruct.SENSOR_MAKER = {'WETLABS' 'WETLABS' 'WETLABS'};
   sensorStruct.SENSOR_MODEL = {'ECO_FLBB2' 'ECO_FLBB2' 'ECO_FLBB2'};
   sensorStruct.SENSOR_SERIAL_NO = repmat({'9999'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_MOUNT = repmat({'MOUNTED_ON_GLIDER'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_ORIENTATION = repmat({''}, size(sensorStruct.SENSOR));

   sensorStruct.PARAMETER = {'CDOM' 'BBP532' 'BBP880'};
   sensorStruct.PARAMETER_SENSOR = {'FLUOROMETER_CDOM' 'BACKSCATTERINGMETER_BBP532' 'BACKSCATTERINGMETER_BBP880'};
   sensorStruct.PARAMETER_DATA_MODE = repmat({'R'}, 1, length(sensorStruct.PARAMETER));
   sensorStruct.PARAMETER_UNITS = repmat({''}, 1, length(sensorStruct.PARAMETER));
   sensorStruct.PARAMETER_ACCURACY = repmat({''}, 1, length(sensorStruct.PARAMETER));
   sensorStruct.PARAMETER_RESOLUTION = repmat({''}, 1, length(sensorStruct.PARAMETER));

elseif (any(strcmp('sci_bb2flsv6_cdom_scaled', availableParam)))

   egoVarNameList = {'CDOM'};
   gliderVarNameList = {'sci_bb2flsv6_cdom_scaled'};
   gliderVarNameListBb2fl = [gliderVarNameListBb2fl gliderVarNameList];

   % retrieve existing sensor data
   sensorStructOld = get_sensor_struct_old(deployJsonData.glider_sensor, deployJsonDirName, gliderVarNameList);

   sensorStruct.SENSOR = {'FLUOROMETER_CDOM'};
   sensorStruct.SENSOR_MAKER = {'WETLABS'};
   sensorStruct.SENSOR_MODEL = {'ECO_FLBB2'};
   sensorStruct.SENSOR_SERIAL_NO = repmat({'9999'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_MOUNT = repmat({'MOUNTED_ON_GLIDER'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_ORIENTATION = repmat({''}, size(sensorStruct.SENSOR));

   sensorStruct.PARAMETER = {'CDOM'};
   sensorStruct.PARAMETER_SENSOR = {'FLUOROMETER_CDOM'};
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
   sensorStruct = update_sensor_data(sensorStruct, sensorStructOld, a_deploymentDirName, 'FLBB2_sv6', a_csvFid);

   % generate sensor json file
   outputFileName = [a_deploymentDirName '_ECO_FLBB2_sv6_' sensorStruct.SENSOR_SERIAL_NO{1} '.json'];
   outputFilePathName = [outputDirName outputFileName];
   sensorFileNameList{end+1} = outputFileName;

   ok = write_json_sensor_file(outputFilePathName, sensorStruct);
   if (ok == 0)
      fprintf('ERROR: Error while generating sensor JSON file: %s\n', outputFilePathName);
   end
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% BB2FL (sv3&sv4&sv5)

sensorStruct = get_sensor_struct;
sensorStructOld = [];
gliderVarNameList = [];
if (any(strcmp('sci_bb2flsv4_chl_scaled', availableParam)) && ...
      any(strcmp('sci_bb2flsv3_b715_scaled', availableParam)) && ...
      any(strcmp('sci_bb2flsv5_cdom_scaled', availableParam)))

   if ~(any(strcmp('sci_bb2flsv4_chl_scaled', gliderVarNameListBb2fl)) && ...
         any(strcmp('sci_bb2flsv3_b715_scaled', gliderVarNameListBb2fl)) && ...
         any(strcmp('sci_bb2flsv5_cdom_scaled', gliderVarNameListBb2fl)))

      egoVarNameList = {'CHLA' 'BBP715' 'CDOM'};
      gliderVarNameList = {'sci_bb2flsv4_chl_scaled' 'sci_bb2flsv3_b715_scaled' 'sci_bb2flsv5_cdom_scaled'};

      % retrieve existing sensor data
      sensorStructOld = get_sensor_struct_old(deployJsonData.glider_sensor, deployJsonDirName, gliderVarNameList);

      sensorStruct.SENSOR = {'FLUOROMETER_CHLA' 'BACKSCATTERINGMETER_BBP715' 'FLUOROMETER_CDOM'};
      sensorStruct.SENSOR_MAKER = {'WETLABS' 'WETLABS' 'WETLABS'};
      sensorStruct.SENSOR_MODEL = {'ECO_FLBBCD' 'ECO_FLBBCD' 'ECO_FLBBCD'};
      sensorStruct.SENSOR_SERIAL_NO = repmat({'9999'}, size(sensorStruct.SENSOR));
      sensorStruct.SENSOR_MOUNT = repmat({'MOUNTED_ON_GLIDER'}, size(sensorStruct.SENSOR));
      sensorStruct.SENSOR_ORIENTATION = repmat({''}, size(sensorStruct.SENSOR));

      sensorStruct.PARAMETER = {'CHLA' 'BBP715' 'CDOM'};
      sensorStruct.PARAMETER_SENSOR = {'FLUOROMETER_CHLA' 'BACKSCATTERINGMETER_BBP715' 'FLUOROMETER_CDOM'};
      sensorStruct.PARAMETER_DATA_MODE = repmat({'R'}, 1, length(sensorStruct.PARAMETER));
      sensorStruct.PARAMETER_UNITS = repmat({''}, 1, length(sensorStruct.PARAMETER));
      sensorStruct.PARAMETER_ACCURACY = repmat({''}, 1, length(sensorStruct.PARAMETER));
      sensorStruct.PARAMETER_RESOLUTION = repmat({''}, 1, length(sensorStruct.PARAMETER));
   end
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
   sensorStruct = update_sensor_data(sensorStruct, sensorStructOld, a_deploymentDirName, 'FLBB2_sv3&sv4&sv5', a_csvFid);

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
% BB3

sensorStruct = get_sensor_struct;
sensorStructOld = [];
gliderVarNameList = [];
if (any(strcmp('sci_bb3slo_b470_sig', availableParam)) && ...
      any(strcmp('sci_bb3slo_b470_scaled', availableParam)) && ...
      any(strcmp('sci_bb3slo_b532_sig', availableParam)) && ...
      any(strcmp('sci_bb3slo_b532_scaled', availableParam)) && ...
      any(strcmp('sci_bb3slo_b660_sig', availableParam)) && ...
      any(strcmp('sci_bb3slo_b660_scaled', availableParam)))

   egoVarNameList = {'BETA_BACKSCATTERING470' 'BBP470' 'BETA_BACKSCATTERING532' 'BBP532' 'BETA_BACKSCATTERING660' 'BBP660'};
   gliderVarNameList = {'sci_bb3slo_b470_sig' 'sci_bb3slo_b470_scaled' 'sci_bb3slo_b532_sig' 'sci_bb3slo_b532_scaled' 'sci_bb3slo_b660_sig' 'sci_bb3slo_b660_scaled'};

   % retrieve existing sensor data
   sensorStructOld = get_sensor_struct_old(deployJsonData.glider_sensor, deployJsonDirName, gliderVarNameList);

   sensorStruct.SENSOR = {'BACKSCATTERINGMETER_BBP470' 'BACKSCATTERINGMETER_BBP532' 'BACKSCATTERINGMETER_BBP660'};
   sensorStruct.SENSOR_MAKER = {'WETLABS' 'WETLABS' 'WETLABS'};
   sensorStruct.SENSOR_MODEL = {'ECO_BB3' 'ECO_BB3' 'ECO_BB3'};
   sensorStruct.SENSOR_SERIAL_NO = repmat({'9999'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_MOUNT = repmat({'MOUNTED_ON_GLIDER'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_ORIENTATION = repmat({''}, size(sensorStruct.SENSOR));

   sensorStruct.PARAMETER = {'BETA_BACKSCATTERING470' 'BBP470' 'BETA_BACKSCATTERING532' 'BBP532' 'BETA_BACKSCATTERING660' 'BBP660'};
   sensorStruct.PARAMETER_SENSOR = {'BACKSCATTERINGMETER_BBP470' 'BACKSCATTERINGMETER_BBP470' 'BACKSCATTERINGMETER_BBP532' 'BACKSCATTERINGMETER_BBP532' 'BACKSCATTERINGMETER_BBP660' 'BACKSCATTERINGMETER_BBP660'};
   sensorStruct.PARAMETER_DATA_MODE = repmat({'R'}, 1, length(sensorStruct.PARAMETER));
   sensorStruct.PARAMETER_UNITS = repmat({''}, 1, length(sensorStruct.PARAMETER));
   sensorStruct.PARAMETER_ACCURACY = repmat({''}, 1, length(sensorStruct.PARAMETER));
   sensorStruct.PARAMETER_RESOLUTION = repmat({''}, 1, length(sensorStruct.PARAMETER));

elseif (any(strcmp('sci_bb3slo_b470_scaled', availableParam)) && ...
      any(strcmp('sci_bb3slo_b532_scaled', availableParam)) && ...
      any(strcmp('sci_bb3slo_b660_scaled', availableParam)))

   egoVarNameList = {'BBP470' 'BBP532' 'BBP660'};
   gliderVarNameList = {'sci_bb3slo_b470_scaled' 'sci_bb3slo_b532_scaled' 'sci_bb3slo_b660_scaled'};

   % retrieve existing sensor data
   sensorStructOld = get_sensor_struct_old(deployJsonData.glider_sensor, deployJsonDirName, gliderVarNameList);

   sensorStruct.SENSOR = {'BACKSCATTERINGMETER_BBP470' 'BACKSCATTERINGMETER_BBP532' 'BACKSCATTERINGMETER_BBP660'};
   sensorStruct.SENSOR_MAKER = {'WETLABS' 'WETLABS' 'WETLABS'};
   sensorStruct.SENSOR_MODEL = {'ECO_BB3' 'ECO_BB3' 'ECO_BB3'};
   sensorStruct.SENSOR_SERIAL_NO = repmat({'9999'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_MOUNT = repmat({'MOUNTED_ON_GLIDER'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_ORIENTATION = repmat({''}, size(sensorStruct.SENSOR));

   sensorStruct.PARAMETER = {'BBP470' 'BBP532' 'BBP660'};
   sensorStruct.PARAMETER_SENSOR = {'BACKSCATTERINGMETER_BBP470' 'BACKSCATTERINGMETER_BBP532' 'BACKSCATTERINGMETER_BBP660'};
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
   sensorStruct = update_sensor_data(sensorStruct, sensorStructOld, a_deploymentDirName, 'BB3', a_csvFid);

   % generate sensor json file
   outputFileName = [a_deploymentDirName '_ECO_BB3_' sensorStruct.SENSOR_SERIAL_NO{1} '.json'];
   outputFilePathName = [outputDirName outputFileName];
   sensorFileNameList{end+1} = outputFileName;

   ok = write_json_sensor_file(outputFilePathName, sensorStruct);
   if (ok == 0)
      fprintf('ERROR: Error while generating sensor JSON file: %s\n', outputFilePathName);
   end
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% BBFL2

sensorStruct = get_sensor_struct;
sensorStructOld = [];
gliderVarNameList = [];
if (any(strcmp('sci_bbfl2s_chlor_scaled', availableParam)) && ...
      any(strcmp('sci_bbfl2s_bb_scaled', availableParam)) && ...
      any(strcmp('sci_bbfl2s_cdom_scaled', availableParam)))

   egoVarNameList = {'CHLA' 'BBP532' 'CDOM'};
   gliderVarNameList = {'sci_bbfl2s_chlor_scaled' 'sci_bbfl2s_bb_scaled' 'sci_bbfl2s_cdom_scaled'};

   % retrieve existing sensor data
   sensorStructOld = get_sensor_struct_old(deployJsonData.glider_sensor, deployJsonDirName, gliderVarNameList);

   sensorStruct.SENSOR = {'FLUOROMETER_CHLA' 'BACKSCATTERINGMETER_BBP532' 'FLUOROMETER_CDOM'};
   sensorStruct.SENSOR_MAKER = {'WETLABS' 'WETLABS' 'WETLABS'};
   sensorStruct.SENSOR_MODEL = {'ECO_FLBBCD' 'ECO_FLBBCD' 'ECO_FLBBCD'};
   sensorStruct.SENSOR_SERIAL_NO = repmat({'9999'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_MOUNT = repmat({'MOUNTED_ON_GLIDER'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_ORIENTATION = repmat({''}, size(sensorStruct.SENSOR));

   sensorStruct.PARAMETER = {'CHLA' 'BBP532' 'CDOM'};
   sensorStruct.PARAMETER_SENSOR = {'FLUOROMETER_CHLA' 'BACKSCATTERINGMETER_BBP532' 'FLUOROMETER_CDOM'};
   sensorStruct.PARAMETER_DATA_MODE = repmat({'R'}, 1, length(sensorStruct.PARAMETER));
   sensorStruct.PARAMETER_UNITS = repmat({''}, 1, length(sensorStruct.PARAMETER));
   sensorStruct.PARAMETER_ACCURACY = repmat({''}, 1, length(sensorStruct.PARAMETER));
   sensorStruct.PARAMETER_RESOLUTION = repmat({''}, 1, length(sensorStruct.PARAMETER));

elseif (any(strcmp('sci_bbfl2s_chlor_scaled', availableParam)) && ...
      any(strcmp('sci_bbfl2s_bb_sig', availableParam)) && ...
      any(strcmp('sci_bbfl2s_cdom_scaled', availableParam)))

   egoVarNameList = {'CHLA' 'BETA_BACKSCATTERING532' 'CDOM'};
   gliderVarNameList = {'sci_bbfl2s_chlor_scaled' 'sci_bbfl2s_bb_sig' 'sci_bbfl2s_cdom_scaled'};

   % retrieve existing sensor data
   sensorStructOld = get_sensor_struct_old(deployJsonData.glider_sensor, deployJsonDirName, gliderVarNameList);

   sensorStruct.SENSOR = {'FLUOROMETER_CHLA' 'BACKSCATTERINGMETER_BBP532' 'FLUOROMETER_CDOM'};
   sensorStruct.SENSOR_MAKER = {'WETLABS' 'WETLABS' 'WETLABS'};
   sensorStruct.SENSOR_MODEL = {'ECO_FLBBCD' 'ECO_FLBBCD' 'ECO_FLBBCD'};
   sensorStruct.SENSOR_SERIAL_NO = repmat({'9999'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_MOUNT = repmat({'MOUNTED_ON_GLIDER'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_ORIENTATION = repmat({''}, size(sensorStruct.SENSOR));

   sensorStruct.PARAMETER = {'CHLA' 'BETA_BACKSCATTERING532' 'CDOM'};
   sensorStruct.PARAMETER_SENSOR = {'FLUOROMETER_CHLA' 'BACKSCATTERINGMETER_BBP532' 'FLUOROMETER_CDOM'};
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
   sensorStruct = update_sensor_data(sensorStruct, sensorStructOld, a_deploymentDirName, 'BBFL2_s', a_csvFid);

   % generate sensor json file
   outputFileName = [a_deploymentDirName '_ECO_FLBBCD_s_' sensorStruct.SENSOR_SERIAL_NO{1} '.json'];
   outputFilePathName = [outputDirName outputFileName];
   sensorFileNameList{end+1} = outputFileName;

   ok = write_json_sensor_file(outputFilePathName, sensorStruct);
   if (ok == 0)
      fprintf('ERROR: Error while generating sensor JSON file: %s\n', outputFilePathName);
   end
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% BBFL2 (sv2)

sensorStruct = get_sensor_struct;
sensorStructOld = [];
gliderVarNameList = [];
if (any(strcmp('sci_bbfl2sv2_fl1_scaled', availableParam)) && ...
      any(strcmp('sci_bbfl2sv2_bb_scaled', availableParam)) && ...
      any(strcmp('sci_bbfl2sv2_fl2_scaled', availableParam)))

   egoVarNameList = {'PE' 'BBP532' 'CDOM'};
   gliderVarNameList = {'sci_bbfl2sv2_fl1_scaled' 'sci_bbfl2sv2_bb_scaled' 'sci_bbfl2sv2_fl2_scaled'};

   % retrieve existing sensor data
   sensorStructOld = get_sensor_struct_old(deployJsonData.glider_sensor, deployJsonDirName, gliderVarNameList);

   sensorStruct.SENSOR = {'FLUOROMETER_PE' 'BACKSCATTERINGMETER_BBP532' 'FLUOROMETER_CDOM'};
   sensorStruct.SENSOR_MAKER = {'WETLABS' 'WETLABS' 'WETLABS'};
   sensorStruct.SENSOR_MODEL = {'ECO_FLBBCD' 'ECO_FLBBCD' 'ECO_FLBBCD'};
   sensorStruct.SENSOR_SERIAL_NO = repmat({'9999'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_MOUNT = repmat({'MOUNTED_ON_GLIDER'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_ORIENTATION = repmat({''}, size(sensorStruct.SENSOR));

   sensorStruct.PARAMETER = {'PE' 'BBP532' 'CDOM'};
   sensorStruct.PARAMETER_SENSOR = {'FLUOROMETER_PE' 'BACKSCATTERINGMETER_BBP532' 'FLUOROMETER_CDOM'};
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
   sensorStruct = update_sensor_data(sensorStruct, sensorStructOld, a_deploymentDirName, 'BBFL2_sv2', a_csvFid);

   % generate sensor json file
   outputFileName = [a_deploymentDirName '_ECO_FLBBCD_sv2_' sensorStruct.SENSOR_SERIAL_NO{1} '.json'];
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
if (any(strcmp('sci_ocr504i_irrad1', availableParam)) && ...
      any(strcmp('sci_ocr504i_irrad2', availableParam)) && ...
      any(strcmp('sci_ocr504i_irrad3', availableParam)) && ...
      any(strcmp('sci_ocr504i_irrad4', availableParam)))

   egoVarNameList = {'DOWN_IRRADIANCE412' 'DOWN_IRRADIANCE443' 'DOWN_IRRADIANCE490' 'DOWN_IRRADIANCE665'};
   gliderVarNameList = {'sci_ocr504i_irrad1' 'sci_ocr504i_irrad2' 'sci_ocr504i_irrad3' 'sci_ocr504i_irrad4'};

   % retrieve existing sensor data
   sensorStructOld = get_sensor_struct_old(deployJsonData.glider_sensor, deployJsonDirName, gliderVarNameList);

   sensorStruct.SENSOR = {'RADIOMETER_DOWN_IRR412' 'RADIOMETER_DOWN_IRR443' 'RADIOMETER_DOWN_IRR490' 'RADIOMETER_DOWN_IRR665'};
   sensorStruct.SENSOR_MAKER = {'SATLANTIC' 'SATLANTIC' 'SATLANTIC' 'SATLANTIC'};
   sensorStruct.SENSOR_MODEL = {'SATLANTIC_OCR504_ICSW' 'SATLANTIC_OCR504_ICSW' 'SATLANTIC_OCR504_ICSW' 'SATLANTIC_OCR504_ICSW'};
   sensorStruct.SENSOR_SERIAL_NO = repmat({'9999'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_MOUNT = repmat({'MOUNTED_ON_GLIDER'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_ORIENTATION = repmat({''}, size(sensorStruct.SENSOR));

   sensorStruct.PARAMETER = {'DOWN_IRRADIANCE412' 'DOWN_IRRADIANCE443' 'DOWN_IRRADIANCE490' 'DOWN_IRRADIANCE665'};
   sensorStruct.PARAMETER_SENSOR = {'RADIOMETER_DOWN_IRR412' 'RADIOMETER_DOWN_IRR443' 'RADIOMETER_DOWN_IRR490' 'RADIOMETER_DOWN_IRR665'};
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
% SUNA

sensorStruct = get_sensor_struct;
sensorStructOld = [];
gliderVarNameList = [];
if (any(strcmp('sci_suna_nitrate_um', availableParam)))

   egoVarNameList = {'MOLAR_NITRATE' 'NITRATE'};
   gliderVarNameList = {'sci_suna_nitrate_um' ''};

   % retrieve existing sensor data
   sensorStructOld = get_sensor_struct_old(deployJsonData.glider_sensor, deployJsonDirName, gliderVarNameList);

   sensorStruct.SENSOR = {'SPECTROPHOTOMETER_NITRATE'};
   sensorStruct.SENSOR_MAKER = {'SATLANTIC'};
   sensorStruct.SENSOR_MODEL = {'SUNA_V2'};
   sensorStruct.SENSOR_SERIAL_NO = repmat({'9999'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_MOUNT = repmat({'MOUNTED_ON_GLIDER'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_ORIENTATION = repmat({''}, size(sensorStruct.SENSOR));

   sensorStruct.PARAMETER = {'MOLAR_NITRATE' 'NITRATE'};
   sensorStruct.PARAMETER_SENSOR = {'SPECTROPHOTOMETER_NITRATE' 'SPECTROPHOTOMETER_NITRATE'};
   sensorStruct.PARAMETER_DATA_MODE = repmat({'R'}, 1, length(sensorStruct.PARAMETER));
   sensorStruct.PARAMETER_UNITS = repmat({''}, 1, length(sensorStruct.PARAMETER));
   sensorStruct.PARAMETER_ACCURACY = repmat({''}, 1, length(sensorStruct.PARAMETER));
   sensorStruct.PARAMETER_RESOLUTION = repmat({''}, 1, length(sensorStruct.PARAMETER));

elseif (any(strcmp('sci_suna_nitrate_concentration', availableParam)))

   egoVarNameList = {'MOLAR_NITRATE' 'NITRATE'};
   gliderVarNameList = {'sci_suna_nitrate_concentration' ''};

   % retrieve existing sensor data
   sensorStructOld = get_sensor_struct_old(deployJsonData.glider_sensor, deployJsonDirName, gliderVarNameList);

   sensorStruct.SENSOR = {'SPECTROPHOTOMETER_NITRATE'};
   sensorStruct.SENSOR_MAKER = {'SATLANTIC'};
   sensorStruct.SENSOR_MODEL = {'SUNA_V2'};
   sensorStruct.SENSOR_SERIAL_NO = repmat({'9999'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_MOUNT = repmat({'MOUNTED_ON_GLIDER'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_ORIENTATION = repmat({''}, size(sensorStruct.SENSOR));

   sensorStruct.PARAMETER = {'MOLAR_NITRATE' 'NITRATE'};
   sensorStruct.PARAMETER_SENSOR = {'SPECTROPHOTOMETER_NITRATE' 'SPECTROPHOTOMETER_NITRATE'};
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
      if (strcmp(egoVarNameList{idP}, 'NITRATE'))
         paramStructList(idP).derivation_comment = 'Not measured by the glider. Calculated by Coriolis';
      end
   end

   sensorStruct.CALIBRATION_COEFFICIENT = [];
   if (~isempty(sensorStructOld))
      if (~isempty(sensorStructOld.CALIBRATION_COEFFICIENT))
         sensorStruct.CALIBRATION_COEFFICIENT = sensorStructOld.CALIBRATION_COEFFICIENT;
      end
   end

   sensorStruct.parametersList = paramStructList;

   % update sensor data structure with existing sensor json file
   sensorStruct = update_sensor_data(sensorStruct, sensorStructOld, a_deploymentDirName, 'SUNA', a_csvFid);

   % generate sensor json file
   outputFileName = [a_deploymentDirName '_SUNA_' sensorStruct.SENSOR_SERIAL_NO{1} '.json'];
   outputFilePathName = [outputDirName outputFileName];
   sensorFileNameList{end+1} = outputFileName;

   ok = write_json_sensor_file(outputFilePathName, sensorStruct);
   if (ok == 0)
      fprintf('ERROR: Error while generating sensor JSON file: %s\n', outputFilePathName);
   end
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% FFL2URRH

sensorStruct = get_sensor_struct;
sensorStructOld = [];
gliderVarNameList = [];
if (any(strcmp('sci_fl2urrh_uran_units', availableParam)) && ...
      any(strcmp('sci_fl2urrh_rhod_units', availableParam)))

   egoVarNameList = {'URANINE' 'RHODAMINE'};
   gliderVarNameList = {'sci_fl2urrh_uran_units' 'sci_fl2urrh_rhod_units'};

   % retrieve existing sensor data
   sensorStructOld = get_sensor_struct_old(deployJsonData.glider_sensor, deployJsonDirName, gliderVarNameList);

   sensorStruct.SENSOR = {'FLUOROMETER_URANINE' 'FLUOROMETER_RHODAMINE'};
   sensorStruct.SENSOR_MAKER = {'WETLABS' 'WETLABS'};
   sensorStruct.SENSOR_MODEL = {'ECO_URRH' 'ECO_URRH'};
   sensorStruct.SENSOR_SERIAL_NO = repmat({'9999'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_MOUNT = repmat({'MOUNTED_ON_GLIDER'}, size(sensorStruct.SENSOR));
   sensorStruct.SENSOR_ORIENTATION = repmat({''}, size(sensorStruct.SENSOR));

   sensorStruct.PARAMETER = {'URANINE' 'RHODAMINE'};
   sensorStruct.PARAMETER_SENSOR = {'FLUOROMETER_URANINE' 'FLUOROMETER_RHODAMINE'};
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
   sensorStruct = update_sensor_data(sensorStruct, sensorStructOld, a_deploymentDirName, 'ECO_URRH', a_csvFid);

   % generate sensor json file
   outputFileName = [a_deploymentDirName '_ECO_URRH_' sensorStruct.SENSOR_SERIAL_NO{1} '.json'];
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
   gliderVarNames = lower({sensorData.parametersList.glider_variable_name});
   for idV = 1:length(a_gliderVarNameList)
      idF1 = cellfun(@(x) strfind(gliderVarNames, x), {a_gliderVarNameList{idV}}, 'UniformOutput', 0);
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
%   10/24/2023 - RNU - creation
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
      % if (~strcmp(a_sensorStruct.SENSOR_MAKER{idS}, a_sensorStructOld.SENSOR_MAKER{idF}))
      %    fprintf('INFO: %s: %s: SENSOR: %s: SENSOR_MAKER updated: %s => %s\n', ...
      %       a_deployName, a_sensorLabel, sensorName, ...
      %       a_sensorStruct.SENSOR_MAKER{idS}, a_sensorStructOld.SENSOR_MAKER{idF});
      %    o_sensorStruct.SENSOR_MAKER{idS} = a_sensorStructOld.SENSOR_MAKER{idF};
      % end
      if (~strcmp(a_sensorStruct.SENSOR_MODEL{idS}, a_sensorStructOld.SENSOR_MODEL{idF}))
         if (~ismember(a_sensorStructOld.SENSOR_MODEL{idF}, {'AANDERAA_OPTODE' 'ECO_FLBBCD' 'ECO_FLNTU' 'ECO_FLBB2' 'SUNA'}))
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
         fprintf(a_csvFid, 'INFO; %s; %s; SENSOR; %s; SENSOR_MOUNT updated;%s;%s\n', ...
            a_deployName, a_sensorLabel, sensorName, ...
            a_sensorStruct.SENSOR_MOUNT{idS}, a_sensorStructOld.SENSOR_MOUNT{idF});
         o_sensorStruct.SENSOR_MOUNT{idS} = a_sensorStructOld.SENSOR_MOUNT{idF};
      end
      if (~strcmp(a_sensorStruct.SENSOR_ORIENTATION{idS}, a_sensorStructOld.SENSOR_ORIENTATION{idF}))
         fprintf(a_csvFid, 'INFO; %s; %s; SENSOR; %s; SENSOR_ORIENTATION updated;%s;%s\n', ...
            a_deployName, a_sensorLabel, sensorName, ...
            a_sensorStruct.SENSOR_ORIENTATION{idS}, a_sensorStructOld.SENSOR_ORIENTATION{idF});
         o_sensorStruct.SENSOR_ORIENTATION{idS} = a_sensorStructOld.SENSOR_ORIENTATION{idF};
      end
   end
end

if (any(strcmp(o_sensorStruct.SENSOR_SERIAL_NO, '9999')))
   if (any(~strcmp(a_sensorStructOld.SENSOR_SERIAL_NO, 'XXXX') & ...
         ~strcmp(a_sensorStructOld.SENSOR_SERIAL_NO, '99999') & ...
         ~strcmp(a_sensorStructOld.SENSOR_SERIAL_NO, '0000')))
      if (length(unique(a_sensorStructOld.SENSOR_SERIAL_NO)) == 1)
         o_sensorStruct.SENSOR_SERIAL_NO = repmat(a_sensorStructOld.SENSOR_SERIAL_NO(1), size(o_sensorStruct.SENSOR));
         for idS = 1:length(a_sensorStruct.SENSOR)
            sensorName = a_sensorStruct.SENSOR{idS};
            fprintf(a_csvFid, 'INFO; %s; %s; SENSOR; %s; SENSOR_SERIAL_NO updated;%s;%s\n', ...
               a_deployName, a_sensorLabel, sensorName, ...
               a_sensorStruct.SENSOR_SERIAL_NO{idS}, a_sensorStructOld.SENSOR_SERIAL_NO{1});
         end
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
      % if (~strcmp(a_sensorStruct.PARAMETER_SENSOR{idP}, a_sensorStructOld.PARAMETER_SENSOR{idF}))
      %    fprintf('INFO: %s: %s: PARAMETER: %s: PARAMETER_SENSOR updated: %s => %s\n', ...
      %       a_deployName, a_sensorLabel, paramName, ...
      %       a_sensorStruct.PARAMETER_SENSOR{idP}, a_sensorStructOld.PARAMETER_SENSOR{idF});
      %    o_sensorStruct.PARAMETER_SENSOR{idP} = a_sensorStructOld.PARAMETER_SENSOR{idF};
      % end
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
      % if (~strcmpi(a_sensorStruct.parametersList(idF1).glider_variable_name, a_sensorStructOld.parametersList(idF2).glider_variable_name))
      %    gliderVarNameOld = a_sensorStructOld.parametersList(idF2).glider_variable_name;
      %    idPt = strfind(gliderVarNameOld, '.');
      %    if (~isempty(idPt))
      %       gliderVarNameOld = gliderVarNameOld(idPt(end)+1:end);
      %    end
      %    if (~strcmpi(a_sensorStruct.parametersList(idF1).glider_variable_name, gliderVarNameOld))
      %       fprintf(a_csvFid, 'INFO; %s; %s; PARAMETER; %s; glider_variable_name updated;%s;%s\n', ...
      %          a_deployName, a_sensorLabel, paramName, ...
      %          a_sensorStruct.parametersList(idF1).glider_variable_name, gliderVarNameOld);
      %       o_sensorStruct.parametersList(idF1).glider_variable_name = gliderVarNameOld;
      %    end
      % end
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
         if (~isempty(a_sensorStructOld.parametersList(idF2).derivation_equation) && ...
               ~ismember(a_sensorStructOld.parametersList(idF2).derivation_equation, {'Not measured by the glider. Calculated by Coriolis', '2'}))
            fprintf(a_csvFid, 'INFO; %s; %s; PARAMETER; %s; derivation_equation updated;"%s";"%s"\n', ...
               a_deployName, a_sensorLabel, paramName, ...
               a_sensorStruct.parametersList(idF1).derivation_equation, a_sensorStructOld.parametersList(idF2).derivation_equation);
            o_sensorStruct.parametersList(idF1).derivation_equation = a_sensorStructOld.parametersList(idF2).derivation_equation;
         end
      end
      if (~strcmp(a_sensorStruct.parametersList(idF1).derivation_coefficient, a_sensorStructOld.parametersList(idF2).derivation_coefficient))
         if (~ismember(a_sensorStructOld.parametersList(idF2).derivation_coefficient, {'Not measured by the glider. Calculated by Coriolis', 'None=None', '2'}))
            fprintf(a_csvFid, 'INFO; %s; %s; PARAMETER; %s; derivation_coefficient updated;"%s";"%s"\n', ...
               a_deployName, a_sensorLabel, paramName, ...
               a_sensorStruct.parametersList(idF1).derivation_coefficient, a_sensorStructOld.parametersList(idF2).derivation_coefficient);
            o_sensorStruct.parametersList(idF1).derivation_coefficient = a_sensorStructOld.parametersList(idF2).derivation_coefficient;
         end
      end
      if (~strcmp(a_sensorStruct.parametersList(idF1).derivation_comment, a_sensorStructOld.parametersList(idF2).derivation_comment))
         if (~ismember(a_sensorStructOld.parametersList(idF2).derivation_comment, {'2'}))
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
%   10/24/2023 - RNU - creation
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
%   10/24/2023 - RNU - creation
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
%   10/24/2023 - RNU - creation
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
