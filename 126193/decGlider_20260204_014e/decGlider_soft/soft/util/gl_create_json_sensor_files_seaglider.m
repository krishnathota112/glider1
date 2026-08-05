% ------------------------------------------------------------------------------
% Generate json sensor files from available data (and existing sensor files).
%
% SYNTAX :
%   gl_create_json_sensor_files_seaglider or
%   gl_create_json_sensor_files_seaglider('data', 'crate_mooset00_38')
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
%   11/30/2023 - RNU - creation
% ------------------------------------------------------------------------------
function gl_create_json_sensor_files_seaglider(varargin)

% top directory of the input deployment directories
INPUT_DATA_DIRECTORY = 'C:\Users\jprannou\_DATA\GLIDER\seaglider\';

% top directory of the output
OUTPUT_DATA_DIRECTORY = 'C:\Users\jprannou\_DATA\GLIDER\out\';

% directory to store the log file
DIR_LOG_FILE = 'C:\Users\jprannou\_RNU\Glider\work\log\';

% directory to store the CSV file
DIR_CSV_FILE = 'C:\Users\jprannou\_RNU\Glider\work\csv\';

% available data mat file
AVAILABLE_DATA_FILE_NAME = 'C:\Users\jprannou\_RNU\Glider\work\seaglider_available_data.mat';

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
logFile = [DIR_LOG_FILE '/' 'gl_create_json_sensor_files_seaglider_' deploymentDir '_' datestr(now, 'yyyymmddTHHMMSS') '.log'];
diary(logFile);
tic;

% create the CSV output file
csvFile = [DIR_CSV_FILE '/' 'gl_create_json_sensor_files_seaglider_' deploymentDir '_' datestr(now, 'yyyymmddTHHMMSS') '.csv'];
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
%   11/30/2023 - RNU - creation
% ------------------------------------------------------------------------------
function gl_create_json_sensor_file(a_deployInputDirName, a_deployOutputDirName, ...
   a_deploymentDirName, a_availableDataFile, a_csvFid)

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
      gl_get_available_data_seaglider(a_deployInputDirName, a_deploymentDirName);
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

switch (dataType)
   case 'nc'

      %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
      % CTD

      sensorStructOld = [];
      gliderVarNameList = [];
      if (any(strcmp('ctd_pressure', availableParam)) && ...
            any(strcmp('temperature_raw', availableParam)) && ...
            any(strcmp('temperature', availableParam)) && ...
            any(strcmp('conductivity_raw', availableParam)) && ...
            any(strcmp('conductivity', availableParam)) && ...
            any(strcmp('salinity_raw', availableParam)) && ...
            any(strcmp('salinity', availableParam)))

         gliderVarNameList = {'ctd_pressure' 'temperature_raw' 'conductivity_raw' 'salinity_raw'};
         gliderAdjVarNameList = {'' 'temperature' 'conductivity' 'salinity'};

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
            paramStructList(idP).glider_adjusted_variable_name = gliderAdjVarNameList{idP};
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
         sensorStruct.PARAMETER_DATA_MODE = repmat({'R'}, size(sensorStruct.PARAMETER));
         sensorStruct.PARAMETER_UNITS = repmat({''}, size(sensorStruct.PARAMETER));
         sensorStruct.PARAMETER_ACCURACY = repmat({''}, size(sensorStruct.PARAMETER));
         sensorStruct.PARAMETER_RESOLUTION = repmat({''}, size(sensorStruct.PARAMETER));

         sensorStruct.CALIBRATION_COEFFICIENT = [];

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

      %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
      % OPTODE_DOXY

      sensorStruct = get_sensor_struct;
      sensorStructOld = [];
      gliderVarNameList = [];
      egoVarNameListDo = [];
      if (any(strcmp('eng_aa4330_TCPhase', availableParam)) && ...
            any(strcmp('eng_aa4330_Temp', availableParam)) && ...
            any(strcmp('eng_aa4330_O2', availableParam)) && ...
            any(strcmp('aanderaa4330_dissolved_oxygen', availableParam)))

         egoVarNameList = {'TPHASE_DOXY' 'TEMP_DOXY' 'MOLAR_DOXY' 'DOXY'};
         gliderVarNameList = {'eng_aa4330_TCPhase' 'eng_aa4330_Temp' 'eng_aa4330_O2' 'aanderaa4330_dissolved_oxygen'};

         % retrieve existing sensor data
         sensorStructOld = get_sensor_struct_old(deployJsonData.glider_sensor, deployJsonDirName, gliderVarNameList);

         sensorStruct.SENSOR = {'OPTODE_DOXY'};
         sensorStruct.SENSOR_MAKER = {'AANDERAA'};
         sensorStruct.SENSOR_MODEL = {'AANDERAA_OPTODE_4330'};
         sensorStruct.SENSOR_SERIAL_NO = repmat({'9999'}, size(sensorStruct.SENSOR));
         sensorStruct.SENSOR_MOUNT = repmat({'MOUNTED_ON_GLIDER'}, size(sensorStruct.SENSOR));
         sensorStruct.SENSOR_ORIENTATION = repmat({''}, size(sensorStruct.SENSOR));

      elseif (any(strcmp('eng_aa4831_TCPhase', availableParam)) && ...
            any(strcmp('eng_aa4831_Temp', availableParam)) && ...
            any(strcmp('eng_aa4831_O2', availableParam)) && ...
            any(strcmp('aanderaa4831_dissolved_oxygen', availableParam)))

         egoVarNameList = {'TPHASE_DOXY' 'TEMP_DOXY' 'MOLAR_DOXY' 'DOXY'};
         gliderVarNameList = {'eng_aa4831_TCPhase' 'eng_aa4831_Temp' 'eng_aa4831_O2' 'aanderaa4831_dissolved_oxygen'};

         % retrieve existing sensor data
         sensorStructOld = get_sensor_struct_old(deployJsonData.glider_sensor, deployJsonDirName, gliderVarNameList);

         sensorStruct.SENSOR = {'OPTODE_DOXY'};
         sensorStruct.SENSOR_MAKER = {'AANDERAA'};
         sensorStruct.SENSOR_MODEL = {'AANDERAA_OPTODE_4831'};
         sensorStruct.SENSOR_SERIAL_NO = repmat({'9999'}, size(sensorStruct.SENSOR));
         sensorStruct.SENSOR_MOUNT = repmat({'MOUNTED_ON_GLIDER'}, size(sensorStruct.SENSOR));
         sensorStruct.SENSOR_ORIENTATION = repmat({''}, size(sensorStruct.SENSOR));

      elseif (any(strcmp('aa4831_TCPhase', availableParam)) && ...
            any(strcmp('aa4831_Temp', availableParam)) && ...
            any(strcmp('aa4831_O2', availableParam)) && ...
            any(strcmp('aanderaa4831_dissolved_oxygen', availableParam)))

         egoVarNameList = {'TPHASE_DOXY' 'TEMP_DOXY' 'MOLAR_DOXY' 'DOXY'};
         gliderVarNameList = {'aa4831_TCPhase' 'aa4831_Temp' 'aa4831_O2' 'aanderaa4831_dissolved_oxygen'};

         % retrieve existing sensor data
         sensorStructOld = get_sensor_struct_old(deployJsonData.glider_sensor, deployJsonDirName, gliderVarNameList);

         sensorStruct.SENSOR = {'OPTODE_DOXY'};
         sensorStruct.SENSOR_MAKER = {'AANDERAA'};
         sensorStruct.SENSOR_MODEL = {'AANDERAA_OPTODE_4831'};
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
         if (~isempty(sensorStructOld))
            if (~isempty(sensorStructOld.CALIBRATION_COEFFICIENT))
               sensorStruct.CALIBRATION_COEFFICIENT = sensorStructOld.CALIBRATION_COEFFICIENT;
            end
         end
         if (any(strcmp('sg_cal_optode_SVUCoef0', availableCoef)) && ...
               any(strcmp('sg_cal_optode_SVUCoef1', availableCoef)) && ...
               any(strcmp('sg_cal_optode_SVUCoef2', availableCoef)) && ...
               any(strcmp('sg_cal_optode_SVUCoef3', availableCoef)) && ...
               any(strcmp('sg_cal_optode_SVUCoef4', availableCoef)) && ...
               any(strcmp('sg_cal_optode_SVUCoef5', availableCoef)) && ...
               any(strcmp('sg_cal_optode_SVUCoef6', availableCoef)) && ...
               any(strcmp('sg_cal_optode_PhaseCoef0', availableCoef)) && ...
               any(strcmp('sg_cal_optode_PhaseCoef1', availableCoef)) && ...
               any(strcmp('sg_cal_optode_PhaseCoef2', availableCoef)) && ...
               any(strcmp('sg_cal_optode_PhaseCoef3', availableCoef)))

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

            if (~isempty(calInfo) && any(strcmp(calInfo(:, 1), 'OPTODE_DOXY') & strcmp(calInfo(:, 2), '202_204_304')))

               OPTODE_DOXY = [];
               OPTODE_DOXY.Case = '202_204_304';
               OPTODE_DOXY.SVUFoilCoef0 = '<nc.data.sg_cal_optode_SVUCoef0>';
               OPTODE_DOXY.SVUFoilCoef1 = '<nc.data.sg_cal_optode_SVUCoef1>';
               OPTODE_DOXY.SVUFoilCoef2 = '<nc.data.sg_cal_optode_SVUCoef2>';
               OPTODE_DOXY.SVUFoilCoef3 = '<nc.data.sg_cal_optode_SVUCoef3>';
               OPTODE_DOXY.SVUFoilCoef4 = '<nc.data.sg_cal_optode_SVUCoef4>';
               OPTODE_DOXY.SVUFoilCoef5 = '<nc.data.sg_cal_optode_SVUCoef5>';
               OPTODE_DOXY.SVUFoilCoef6 = '<nc.data.sg_cal_optode_SVUCoef6>';
               OPTODE_DOXY.PhaseCoef0 = '<nc.data.sg_cal_optode_PhaseCoef0>';
               OPTODE_DOXY.PhaseCoef1 = '<nc.data.sg_cal_optode_PhaseCoef1>';
               OPTODE_DOXY.PhaseCoef2 = '<nc.data.sg_cal_optode_PhaseCoef2>';
               OPTODE_DOXY.PhaseCoef3 = '<nc.data.sg_cal_optode_PhaseCoef3>';
               sensorStruct.CALIBRATION_COEFFICIENT.OPTODE_DOXY = OPTODE_DOXY;

               egoVarName = 'DOXY';
               if (any(strcmp(egoVarName, egoVarNameListDo)))
                  cpt = 2;
                  egoVarName = [egoVarName num2str(cpt)];
                  while (any(strcmp(egoVarName, egoVarNameListDo)))
                     cpt = cpt + 1;
                     egoVarName = [egoVarNameList{idP} num2str(cpt)];
                  end
               end
               egoVarNameListDo{end+1} = egoVarName;
               sensorStruct.PARAMETER{end+1} = egoVarName;
               sensorStruct.PARAMETER_SENSOR{end+1} = 'OPTODE_DOXY';
               sensorStruct.PARAMETER_DATA_MODE{end+1} = 'R';
               sensorStruct.PARAMETER_UNITS{end+1} = '';
               sensorStruct.PARAMETER_ACCURACY{end+1} = '';
               sensorStruct.PARAMETER_RESOLUTION{end+1} = '';

               paramStructList(end+1) = get_param_struct;
               paramStructList(end).ego_variable_name = egoVarName;
               paramStructList(end).derivation_comment = 'Not measured by the glider. Calculated by Coriolis';
               paramStructList(end).processing_id = '202_204_304';
            end
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
      % IDO_DOXY

      sensorStruct = get_sensor_struct;
      sensorStructOld = [];
      gliderVarNameList = [];
      if (any(strcmp('eng_sbe43_O2Freq', availableParam)) && ...
            any(strcmp('sbe43_dissolved_oxygen', availableParam)))

         egoVarNameList = {'FREQUENCY_DOXY' 'DOXY'};
         gliderVarNameList = {'eng_sbe43_O2Freq' 'sbe43_dissolved_oxygen'};

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

      %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
      % FLNTU

      sensorStruct = get_sensor_struct;
      sensorStructOld = [];
      gliderVarNameList = [];
      if (any(strcmp('wlflntu_FL1sig', availableParam)) && ...
            any(strcmp('wlflntu_temp', availableParam)) && ...
            any(strcmp('wlflntu_NTsig', availableParam)))

         egoVarNameList = {'FLUORESCENCE_CHLA' 'TEMP_CPU_CHLA' 'SIDE_SCATTERING_TURBIDITY'};
         gliderVarNameList = {'wlflntu_FL1sig' 'wlflntu_temp' 'wlflntu_NTsig'};

         % retrieve existing sensor data
         sensorStructOld = get_sensor_struct_old(deployJsonData.glider_sensor, deployJsonDirName, gliderVarNameList);

         sensorStruct.SENSOR = {'FLUOROMETER_CHLA' 'BACKSCATTERINGMETER_TURBIDITY'};
         sensorStruct.SENSOR_MAKER = {'WETLABS' 'WETLABS'};
         sensorStruct.SENSOR_MODEL = {'ECO_FLNTU' 'ECO_FLNTU'};
         sensorStruct.SENSOR_SERIAL_NO = repmat({'9999'}, size(sensorStruct.SENSOR));
         sensorStruct.SENSOR_MOUNT = repmat({'MOUNTED_ON_GLIDER'}, size(sensorStruct.SENSOR));
         sensorStruct.SENSOR_ORIENTATION = repmat({''}, size(sensorStruct.SENSOR));

         sensorStruct.PARAMETER = {'FLUORESCENCE_CHLA' 'TEMP_CPU_CHLA' 'SIDE_SCATTERING_TURBIDITY'};
         sensorStruct.PARAMETER_SENSOR = {'FLUOROMETER_CHLA' 'FLUOROMETER_CHLA' 'BACKSCATTERINGMETER_TURBIDITY'};
         sensorStruct.PARAMETER_DATA_MODE = repmat({'R'}, size(sensorStruct.PARAMETER));
         sensorStruct.PARAMETER_UNITS = repmat({''}, size(sensorStruct.PARAMETER));
         sensorStruct.PARAMETER_ACCURACY = repmat({''}, size(sensorStruct.PARAMETER));
         sensorStruct.PARAMETER_RESOLUTION = repmat({''}, size(sensorStruct.PARAMETER));
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

         sensorStruct.CALIBRATION_COEFFICIENT = [];
         if (any(strcmp('sg_cal_WETLabsCalData_wlflntu_Chlorophyll_scaleFactor', availableCoef)) || ...
               any(strcmp('sg_cal_WETLabsCalData_wlflntu_Chlorophyll_darkCounts', availableCoef)))
            FLUOROMETER_CHLA = [];
            FLUOROMETER_CHLA.ScaleFactCHLA = '<nc.data.sg_cal_WETLabsCalData_wlflntu_Chlorophyll_scaleFactor>';
            FLUOROMETER_CHLA.DarkCountCHLA = '<nc.data.sg_cal_WETLabsCalData_wlflntu_Chlorophyll_darkCounts>';
            sensorStruct.CALIBRATION_COEFFICIENT.FLUOROMETER_CHLA = FLUOROMETER_CHLA;

            sensorStruct.PARAMETER{end+1} = 'CHLA';
            sensorStruct.PARAMETER_SENSOR{end+1} = 'FLUOROMETER_CHLA';
            sensorStruct.PARAMETER_DATA_MODE{end+1} = 'R';
            sensorStruct.PARAMETER_UNITS{end+1} = '';
            sensorStruct.PARAMETER_ACCURACY{end+1} = '';
            sensorStruct.PARAMETER_RESOLUTION{end+1} = '';

            paramStructList(end+1) = get_param_struct;
            paramStructList(end).ego_variable_name = 'CHLA';
            paramStructList(end).derivation_comment = 'Not measured by the glider. Calculated by Coriolis';
         end
         if (any(strcmp('sg_cal_WETLabsCalData_wlflntu_NT_scaleFactor', availableCoef)) || ...
               any(strcmp('sg_cal_WETLabsCalData_wlflntu_NT_darkCounts', availableCoef)))
            BACKSCATTERINGMETER_TURBIDITY = [];
            BACKSCATTERINGMETER_TURBIDITY.ScaleFactTURBIDITY = '<nc.data.sg_cal_WETLabsCalData_wlflntu_NT_scaleFactor>';
            BACKSCATTERINGMETER_TURBIDITY.DarkCountTURBIDITY = '<nc.data.sg_cal_WETLabsCalData_wlflntu_NT_darkCounts>';
            sensorStruct.CALIBRATION_COEFFICIENT.BACKSCATTERINGMETER_TURBIDITY = BACKSCATTERINGMETER_TURBIDITY;

            sensorStruct.PARAMETER{end+1} = 'TURBIDITY';
            sensorStruct.PARAMETER_SENSOR{end+1} = 'BACKSCATTERINGMETER_TURBIDITY';
            sensorStruct.PARAMETER_DATA_MODE{end+1} = 'R';
            sensorStruct.PARAMETER_UNITS{end+1} = '';
            sensorStruct.PARAMETER_ACCURACY{end+1} = '';
            sensorStruct.PARAMETER_RESOLUTION{end+1} = '';

            paramStructList(end+1) = get_param_struct;
            paramStructList(end).ego_variable_name = 'TURBIDITY';
            paramStructList(end).derivation_comment = 'Not measured by the glider. Calculated by Coriolis';
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

      %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
      % NTUFL2

      sensorStruct = get_sensor_struct;
      sensorStructOld = [];
      gliderVarNameList = [];
      if (any(strcmp('eng_wlntufl2_FL1sig', availableParam)) && ...
            any(strcmp('eng_wlntufl2_temp', availableParam)) && ...
            any(strcmp('eng_wlntufl2_FL2sig', availableParam)) && ...
            any(strcmp('eng_wlntufl2_NTsig', availableParam)))

         egoVarNameList = {'FLUORESCENCE_CHLA' 'TEMP_CPU_CHLA' 'FLUORESCENCE_CDOM' 'SIDE_SCATTERING_TURBIDITY'};
         gliderVarNameList = {'eng_wlntufl2_FL1sig' 'eng_wlntufl2_temp' 'eng_wlntufl2_FL2sig' 'eng_wlntufl2_NTsig'};

         % retrieve existing sensor data
         sensorStructOld = get_sensor_struct_old(deployJsonData.glider_sensor, deployJsonDirName, gliderVarNameList);

         sensorStruct.SENSOR = {'FLUOROMETER_CHLA' 'FLUOROMETER_CDOM' 'BACKSCATTERINGMETER_TURBIDITY'};
         sensorStruct.SENSOR_MAKER = {'WETLABS' 'WETLABS' 'WETLABS'};
         sensorStruct.SENSOR_MODEL = {'ECO_FLNTU' 'ECO_FLNTU' 'ECO_FLNTU'};
         sensorStruct.SENSOR_SERIAL_NO = repmat({'9999'}, size(sensorStruct.SENSOR));
         sensorStruct.SENSOR_MOUNT = repmat({'MOUNTED_ON_GLIDER'}, size(sensorStruct.SENSOR));
         sensorStruct.SENSOR_ORIENTATION = repmat({''}, size(sensorStruct.SENSOR));

         sensorStruct.PARAMETER = {'FLUORESCENCE_CHLA' 'TEMP_CPU_CHLA' 'FLUORESCENCE_CDOM' 'SIDE_SCATTERING_TURBIDITY'};
         sensorStruct.PARAMETER_SENSOR = {'FLUOROMETER_CHLA' 'FLUOROMETER_CHLA' 'FLUOROMETER_CDOM' 'BACKSCATTERINGMETER_TURBIDITY'};
         sensorStruct.PARAMETER_DATA_MODE = repmat({'R'}, size(sensorStruct.PARAMETER));
         sensorStruct.PARAMETER_UNITS = repmat({''}, size(sensorStruct.PARAMETER));
         sensorStruct.PARAMETER_ACCURACY = repmat({''}, size(sensorStruct.PARAMETER));
         sensorStruct.PARAMETER_RESOLUTION = repmat({''}, size(sensorStruct.PARAMETER));
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

         sensorStruct.CALIBRATION_COEFFICIENT = [];
         if (any(strcmp('sg_cal_WETLabsCalData_wlntufl2_Chlorophyll_scaleFactor', availableCoef)) || ...
               any(strcmp('sg_cal_WETLabsCalData_wlntufl2_Chlorophyll_darkCounts', availableCoef)))
            FLUOROMETER_CHLA = [];
            FLUOROMETER_CHLA.ScaleFactCHLA = '<nc.data.sg_cal_WETLabsCalData_wlntufl2_Chlorophyll_scaleFactor>';
            FLUOROMETER_CHLA.DarkCountCHLA = '<nc.data.sg_cal_WETLabsCalData_wlntufl2_Chlorophyll_darkCounts>';
            sensorStruct.CALIBRATION_COEFFICIENT.FLUOROMETER_CHLA = FLUOROMETER_CHLA;

            sensorStruct.PARAMETER{end+1} = 'CHLA';
            sensorStruct.PARAMETER_SENSOR{end+1} = 'FLUOROMETER_CHLA';
            sensorStruct.PARAMETER_DATA_MODE{end+1} = 'R';
            sensorStruct.PARAMETER_UNITS{end+1} = '';
            sensorStruct.PARAMETER_ACCURACY{end+1} = '';
            sensorStruct.PARAMETER_RESOLUTION{end+1} = '';

            paramStructList(end+1) = get_param_struct;
            paramStructList(end).ego_variable_name = 'CHLA';
            paramStructList(end).derivation_comment = 'Not measured by the glider. Calculated by Coriolis';
         end
         if (any(strcmp('sg_cal_WETLabsCalData_wlntufl2_CDOM_scaleFactor', availableCoef)) || ...
               any(strcmp('sg_cal_WETLabsCalData_wlntufl2_CDOM_darkCounts', availableCoef)))
            FLUOROMETER_CDOM = [];
            FLUOROMETER_CDOM.ScaleFactCDOM = '<nc.data.sg_cal_WETLabsCalData_wlntufl2_CDOM_scaleFactor>';
            FLUOROMETER_CDOM.DarkCountCDOM = '<nc.data.sg_cal_WETLabsCalData_wlntufl2_CDOM_darkCounts>';
            sensorStruct.CALIBRATION_COEFFICIENT.FLUOROMETER_CDOM = FLUOROMETER_CDOM;

            sensorStruct.PARAMETER{end+1} = 'CDOM';
            sensorStruct.PARAMETER_SENSOR{end+1} = 'FLUOROMETER_CDOM';
            sensorStruct.PARAMETER_DATA_MODE{end+1} = 'R';
            sensorStruct.PARAMETER_UNITS{end+1} = '';
            sensorStruct.PARAMETER_ACCURACY{end+1} = '';
            sensorStruct.PARAMETER_RESOLUTION{end+1} = '';

            paramStructList(end+1) = get_param_struct;
            paramStructList(end).ego_variable_name = 'CDOM';
            paramStructList(end).derivation_comment = 'Not measured by the glider. Calculated by Coriolis';
         end
         if (any(strcmp('sg_cal_WETLabsCalData_wlntufl2_NT_scaleFactor', availableCoef)) || ...
               any(strcmp('sg_cal_WETLabsCalData_wlntufl2_NT_darkCounts', availableCoef)))
            BACKSCATTERINGMETER_TURBIDITY = [];
            BACKSCATTERINGMETER_TURBIDITY.ScaleFactTURBIDITY = '<nc.data.sg_cal_WETLabsCalData_wlntufl2_NT_scaleFactor>';
            BACKSCATTERINGMETER_TURBIDITY.DarkCountTURBIDITY = '<nc.data.sg_cal_WETLabsCalData_wlntufl2_NT_darkCounts>';
            sensorStruct.CALIBRATION_COEFFICIENT.BACKSCATTERINGMETER_TURBIDITY = BACKSCATTERINGMETER_TURBIDITY;

            sensorStruct.PARAMETER{end+1} = 'TURBIDITY';
            sensorStruct.PARAMETER_SENSOR{end+1} = 'BACKSCATTERINGMETER_TURBIDITY';
            sensorStruct.PARAMETER_DATA_MODE{end+1} = 'R';
            sensorStruct.PARAMETER_UNITS{end+1} = '';
            sensorStruct.PARAMETER_ACCURACY{end+1} = '';
            sensorStruct.PARAMETER_RESOLUTION{end+1} = '';

            paramStructList(end+1) = get_param_struct;
            paramStructList(end).ego_variable_name = 'TURBIDITY';
            paramStructList(end).derivation_comment = 'Not measured by the glider. Calculated by Coriolis';
         end

         sensorStruct.parametersList = paramStructList;

         % update sensor data structure with existing sensor json file
         sensorStruct = update_sensor_data(sensorStruct, sensorStructOld, a_deploymentDirName, 'NTUFL2', a_csvFid);

         % generate sensor json file
         outputFileName = [a_deploymentDirName '_ECO_FLNTU_' sensorStruct.SENSOR_SERIAL_NO{1} '.json'];
         outputFilePathName = [outputDirName outputFileName];
         sensorFileNameList{end+1} = outputFileName;

         ok = write_json_sensor_file(outputFilePathName, sensorStruct);
         if (ok == 0)
            fprintf('ERROR: Error while generating sensor JSON file: %s\n', outputFilePathName);
         end
      end

      %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
      % BBFL2

      sensorStruct = get_sensor_struct;
      sensorStructOld = [];
      gliderVarNameList = [];
      if (any(strcmp('eng_wlbbfl2_FL1sig', availableParam)) && ...
            any(strcmp('eng_wlbbfl2_temp', availableParam)) && ...
            any(strcmp('eng_wlbbfl2_BB1sig', availableParam)) && ...
            any(strcmp('eng_wlbbfl2_FL2sig', availableParam)))

         egoVarNameList = {'FLUORESCENCE_CHLA' 'TEMP_CPU_CHLA' 'BETA_BACKSCATTERING700' 'FLUORESCENCE_CDOM'};
         gliderVarNameList = {'eng_wlbbfl2_FL1sig' 'eng_wlbbfl2_temp' 'eng_wlbbfl2_BB1sig' 'eng_wlbbfl2_FL2sig'};

         % retrieve existing sensor data
         sensorStructOld = get_sensor_struct_old(deployJsonData.glider_sensor, deployJsonDirName, gliderVarNameList);

         sensorStruct.SENSOR = {'FLUOROMETER_CHLA' 'BACKSCATTERINGMETER_BBP700' 'FLUOROMETER_CDOM'};
         sensorStruct.SENSOR_MAKER = {'WETLABS' 'WETLABS' 'WETLABS'};
         sensorStruct.SENSOR_MODEL = {'ECO_FLBBCD' 'ECO_FLBBCD' 'ECO_FLBBCD'};
         sensorStruct.SENSOR_SERIAL_NO = repmat({'9999'}, size(sensorStruct.SENSOR));
         sensorStruct.SENSOR_MOUNT = repmat({'MOUNTED_ON_GLIDER'}, size(sensorStruct.SENSOR));
         sensorStruct.SENSOR_ORIENTATION = repmat({''}, size(sensorStruct.SENSOR));

         sensorStruct.PARAMETER = {'FLUORESCENCE_CHLA' 'TEMP_CPU_CHLA' 'BETA_BACKSCATTERING700' 'FLUORESCENCE_CDOM'};
         sensorStruct.PARAMETER_SENSOR = {'FLUOROMETER_CHLA' 'FLUOROMETER_CHLA' 'BACKSCATTERINGMETER_BBP700' 'FLUOROMETER_CDOM'};
         sensorStruct.PARAMETER_DATA_MODE = repmat({'R'}, size(sensorStruct.PARAMETER));
         sensorStruct.PARAMETER_UNITS = repmat({''}, size(sensorStruct.PARAMETER));
         sensorStruct.PARAMETER_ACCURACY = repmat({''}, size(sensorStruct.PARAMETER));
         sensorStruct.PARAMETER_RESOLUTION = repmat({''}, size(sensorStruct.PARAMETER));

      elseif (any(strcmp('wlbbfl2_FL1sig', availableParam)) && ...
            any(strcmp('wlbbfl2_temp', availableParam)) && ...
            any(strcmp('wlbbfl2_BB1sig', availableParam)) && ...
            any(strcmp('wlbbfl2_FL2sig', availableParam)))

         egoVarNameList = {'FLUORESCENCE_CHLA' 'TEMP_CPU_CHLA' 'BETA_BACKSCATTERING700' 'FLUORESCENCE_CDOM'};
         gliderVarNameList = {'wlbbfl2_FL1sig' 'wlbbfl2_temp' 'wlbbfl2_BB1sig' 'wlbbfl2_FL2sig'};

         % retrieve existing sensor data
         sensorStructOld = get_sensor_struct_old(deployJsonData.glider_sensor, deployJsonDirName, gliderVarNameList);

         sensorStruct.SENSOR = {'FLUOROMETER_CHLA' 'BACKSCATTERINGMETER_BBP700' 'FLUOROMETER_CDOM'};
         sensorStruct.SENSOR_MAKER = {'WETLABS' 'WETLABS' 'WETLABS'};
         sensorStruct.SENSOR_MODEL = {'ECO_FLBBCD' 'ECO_FLBBCD' 'ECO_FLBBCD'};
         sensorStruct.SENSOR_SERIAL_NO = repmat({'9999'}, size(sensorStruct.SENSOR));
         sensorStruct.SENSOR_MOUNT = repmat({'MOUNTED_ON_GLIDER'}, size(sensorStruct.SENSOR));
         sensorStruct.SENSOR_ORIENTATION = repmat({''}, size(sensorStruct.SENSOR));

         sensorStruct.PARAMETER = {'FLUORESCENCE_CHLA' 'TEMP_CPU_CHLA' 'BETA_BACKSCATTERING700' 'FLUORESCENCE_CDOM'};
         sensorStruct.PARAMETER_SENSOR = {'FLUOROMETER_CHLA' 'FLUOROMETER_CHLA' 'BACKSCATTERINGMETER_BBP700' 'FLUOROMETER_CDOM'};
         sensorStruct.PARAMETER_DATA_MODE = repmat({'R'}, size(sensorStruct.PARAMETER));
         sensorStruct.PARAMETER_UNITS = repmat({''}, size(sensorStruct.PARAMETER));
         sensorStruct.PARAMETER_ACCURACY = repmat({''}, size(sensorStruct.PARAMETER));
         sensorStruct.PARAMETER_RESOLUTION = repmat({''}, size(sensorStruct.PARAMETER));
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

         sensorStruct.CALIBRATION_COEFFICIENT = [];
         if (any(strcmp('sg_cal_WETLabsCalData_wlbbfl2_Chlorophyll_scaleFactor', availableCoef)) || ...
               any(strcmp('sg_cal_WETLabsCalData_wlbbfl2_Chlorophyll_darkCounts', availableCoef)))
            FLUOROMETER_CHLA = [];
            FLUOROMETER_CHLA.ScaleFactCHLA = '<nc.data.sg_cal_WETLabsCalData_wlbbfl2_Chlorophyll_scaleFactor>';
            FLUOROMETER_CHLA.DarkCountCHLA = '<nc.data.sg_cal_WETLabsCalData_wlbbfl2_Chlorophyll_darkCounts>';
            sensorStruct.CALIBRATION_COEFFICIENT.FLUOROMETER_CHLA = FLUOROMETER_CHLA;

            sensorStruct.PARAMETER{end+1} = 'CHLA';
            sensorStruct.PARAMETER_SENSOR{end+1} = 'FLUOROMETER_CHLA';
            sensorStruct.PARAMETER_DATA_MODE{end+1} = 'R';
            sensorStruct.PARAMETER_UNITS{end+1} = '';
            sensorStruct.PARAMETER_ACCURACY{end+1} = '';
            sensorStruct.PARAMETER_RESOLUTION{end+1} = '';

            paramStructList(end+1) = get_param_struct;
            paramStructList(end).ego_variable_name = 'CHLA';
            paramStructList(end).derivation_comment = 'Not measured by the glider. Calculated by Coriolis';
         elseif (any(strcmp('sg_cal_WETLabsCalData_wlbbfl2vmt_Chlsig_scaleFactor', availableCoef)) || ...
               any(strcmp('sg_cal_WETLabsCalData_wlbbfl2vmt_Chlsig_darkCounts', availableCoef)))
            FLUOROMETER_CHLA = [];
            FLUOROMETER_CHLA.ScaleFactCHLA = '<nc.data.sg_cal_WETLabsCalData_wlbbfl2vmt_Chlsig_scaleFactor>';
            FLUOROMETER_CHLA.DarkCountCHLA = '<nc.data.sg_cal_WETLabsCalData_wlbbfl2vmt_Chlsig_darkCounts>';
            sensorStruct.CALIBRATION_COEFFICIENT.FLUOROMETER_CHLA = FLUOROMETER_CHLA;

            sensorStruct.PARAMETER{end+1} = 'CHLA';
            sensorStruct.PARAMETER_SENSOR{end+1} = 'FLUOROMETER_CHLA';
            sensorStruct.PARAMETER_DATA_MODE{end+1} = 'R';
            sensorStruct.PARAMETER_UNITS{end+1} = '';
            sensorStruct.PARAMETER_ACCURACY{end+1} = '';
            sensorStruct.PARAMETER_RESOLUTION{end+1} = '';

            paramStructList(end+1) = get_param_struct;
            paramStructList(end).ego_variable_name = 'CHLA';
            paramStructList(end).derivation_comment = 'Not measured by the glider. Calculated by Coriolis';
         end
         if (any(strcmp('sg_cal_WETLabsCalData_wlbbfl2_Scatter700_scaleFactor', availableCoef)) || ...
               any(strcmp('sg_cal_WETLabsCalData_wlbbfl2_Scatter700_darkCounts', availableCoef)))
            BACKSCATTERINGMETER_BBP700 = [];
            BACKSCATTERINGMETER_BBP700.ScaleFactBBP700 = '<nc.data.sg_cal_WETLabsCalData_wlbbfl2_Scatter700_scaleFactor>';
            BACKSCATTERINGMETER_BBP700.DarkCountBBP700 = '<nc.data.sg_cal_WETLabsCalData_wlbbfl2_Scatter700_darkCounts>';
            BACKSCATTERINGMETER_BBP700.KhiCoefBBP700 = 1.076;
            BACKSCATTERINGMETER_BBP700.MeasAngleBBP700 = 124;
            sensorStruct.CALIBRATION_COEFFICIENT.BACKSCATTERINGMETER_BBP700 = BACKSCATTERINGMETER_BBP700;

            sensorStruct.PARAMETER{end+1} = 'BBP700';
            sensorStruct.PARAMETER_SENSOR{end+1} = 'BACKSCATTERINGMETER_BBP700';
            sensorStruct.PARAMETER_DATA_MODE{end+1} = 'R';
            sensorStruct.PARAMETER_UNITS{end+1} = '';
            sensorStruct.PARAMETER_ACCURACY{end+1} = '';
            sensorStruct.PARAMETER_RESOLUTION{end+1} = '';

            paramStructList(end+1) = get_param_struct;
            paramStructList(end).ego_variable_name = 'BBP700';
            paramStructList(end).derivation_comment = 'Not measured by the glider. Calculated by Coriolis';
         elseif (any(strcmp('sg_cal_WETLabsCalData_wlbbfl2vmt_BB1sig_scaleFactor', availableCoef)) || ...
               any(strcmp('sg_cal_WETLabsCalData_wlbbfl2vmt_BB1sig_darkCounts', availableCoef)))
            BACKSCATTERINGMETER_BBP700 = [];
            BACKSCATTERINGMETER_BBP700.ScaleFactBBP700 = '<nc.data.sg_cal_WETLabsCalData_wlbbfl2vmt_BB1sig_scaleFactor>';
            BACKSCATTERINGMETER_BBP700.DarkCountBBP700 = '<nc.data.sg_cal_WETLabsCalData_wlbbfl2vmt_BB1sig_darkCounts>';
            BACKSCATTERINGMETER_BBP700.KhiCoefBBP700 = 1.076;
            BACKSCATTERINGMETER_BBP700.MeasAngleBBP700 = 124;
            sensorStruct.CALIBRATION_COEFFICIENT.BACKSCATTERINGMETER_BBP700 = BACKSCATTERINGMETER_BBP700;

            sensorStruct.PARAMETER{end+1} = 'BBP700';
            sensorStruct.PARAMETER_SENSOR{end+1} = 'BACKSCATTERINGMETER_BBP700';
            sensorStruct.PARAMETER_DATA_MODE{end+1} = 'R';
            sensorStruct.PARAMETER_UNITS{end+1} = '';
            sensorStruct.PARAMETER_ACCURACY{end+1} = '';
            sensorStruct.PARAMETER_RESOLUTION{end+1} = '';

            paramStructList(end+1) = get_param_struct;
            paramStructList(end).ego_variable_name = 'BBP700';
            paramStructList(end).derivation_comment = 'Not measured by the glider. Calculated by Coriolis';
         end
         if (any(strcmp('sg_cal_WETLabsCalData_wlbbfl2_CDOM_scaleFactor', availableCoef)) || ...
               any(strcmp('sg_cal_WETLabsCalData_wlbbfl2_CDOM_darkCounts', availableCoef)))
            FLUOROMETER_CDOM = [];
            FLUOROMETER_CDOM.ScaleFactCDOM = '<nc.data.sg_cal_WETLabsCalData_wlbbfl2_CDOM_scaleFactor>';
            FLUOROMETER_CDOM.DarkCountCDOM = '<nc.data.sg_cal_WETLabsCalData_wlbbfl2_CDOM_darkCounts>';
            sensorStruct.CALIBRATION_COEFFICIENT.FLUOROMETER_CDOM = FLUOROMETER_CDOM;

            sensorStruct.PARAMETER{end+1} = 'CDOM';
            sensorStruct.PARAMETER_SENSOR{end+1} = 'FLUOROMETER_CDOM';
            sensorStruct.PARAMETER_DATA_MODE{end+1} = 'R';
            sensorStruct.PARAMETER_UNITS{end+1} = '';
            sensorStruct.PARAMETER_ACCURACY{end+1} = '';
            sensorStruct.PARAMETER_RESOLUTION{end+1} = '';

            paramStructList(end+1) = get_param_struct;
            paramStructList(end).ego_variable_name = 'CDOM';
            paramStructList(end).derivation_comment = 'Not measured by the glider. Calculated by Coriolis';
         elseif (any(strcmp('sg_cal_WETLabsCalData_wlbbfl2vmt_Cdomsig_scaleFactor', availableCoef)) || ...
               any(strcmp('sg_cal_WETLabsCalData_wlbbfl2vmt_Cdomsig_darkCounts', availableCoef)))
            FLUOROMETER_CDOM = [];
            FLUOROMETER_CDOM.ScaleFactCDOM = '<nc.data.sg_cal_WETLabsCalData_wlbbfl2vmt_Cdomsig_scaleFactor>';
            FLUOROMETER_CDOM.DarkCountCDOM = '<nc.data.sg_cal_WETLabsCalData_wlbbfl2vmt_Cdomsig_darkCounts>';
            sensorStruct.CALIBRATION_COEFFICIENT.FLUOROMETER_CDOM = FLUOROMETER_CDOM;

            sensorStruct.PARAMETER{end+1} = 'CDOM';
            sensorStruct.PARAMETER_SENSOR{end+1} = 'FLUOROMETER_CDOM';
            sensorStruct.PARAMETER_DATA_MODE{end+1} = 'R';
            sensorStruct.PARAMETER_UNITS{end+1} = '';
            sensorStruct.PARAMETER_ACCURACY{end+1} = '';
            sensorStruct.PARAMETER_RESOLUTION{end+1} = '';

            paramStructList(end+1) = get_param_struct;
            paramStructList(end).ego_variable_name = 'CDOM';
            paramStructList(end).derivation_comment = 'Not measured by the glider. Calculated by Coriolis';
         end

         sensorStruct.parametersList = paramStructList;

         % update sensor data structure with existing sensor json file
         sensorStruct = update_sensor_data(sensorStruct, sensorStructOld, a_deploymentDirName, 'BBFL2', a_csvFid);

         % generate sensor json file
         outputFileName = [a_deploymentDirName '_ECO_FLBBCD_' sensorStruct.SENSOR_SERIAL_NO{1} '.json'];
         outputFilePathName = [outputDirName outputFileName];
         sensorFileNameList{end+1} = outputFileName;

         ok = write_json_sensor_file(outputFilePathName, sensorStruct);
         if (ok == 0)
            fprintf('ERROR: Error while generating sensor JSON file: %s\n', outputFilePathName);
         end
      end

      %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
      % BB2FL

      sensorStruct = get_sensor_struct;
      sensorStructOld = [];
      gliderVarNameList = [];
      if (any(strcmp('eng_wlbb2fl_FL1sig', availableParam)) && ...
            any(strcmp('eng_wlbb2fl_temp', availableParam)) && ...
            any(strcmp('eng_wlbb2fl_BB1sig', availableParam)) && ...
            any(strcmp('eng_wlbb2fl_BB2sig', availableParam)))

         egoVarNameList = {'FLUORESCENCE_CHLA' 'TEMP_CPU_CHLA' 'BETA_BACKSCATTERING532' 'BETA_BACKSCATTERING880'};
         gliderVarNameList = {'eng_wlbb2fl_FL1sig' 'eng_wlbb2fl_temp' 'eng_wlbb2fl_BB1sig' 'eng_wlbb2fl_BB2sig'};

         % retrieve existing sensor data
         sensorStructOld = get_sensor_struct_old(deployJsonData.glider_sensor, deployJsonDirName, gliderVarNameList);

         sensorStruct.SENSOR = {'FLUOROMETER_CHLA' 'BACKSCATTERINGMETER_BBP532' 'BACKSCATTERINGMETER_BBP880'};
         sensorStruct.SENSOR_MAKER = {'WETLABS' 'WETLABS' 'WETLABS'};
         sensorStruct.SENSOR_MODEL = {'ECO_FLBB2' 'ECO_FLBB2' 'ECO_FLBB2'};
         sensorStruct.SENSOR_SERIAL_NO = repmat({'9999'}, size(sensorStruct.SENSOR));
         sensorStruct.SENSOR_MOUNT = repmat({'MOUNTED_ON_GLIDER'}, size(sensorStruct.SENSOR));
         sensorStruct.SENSOR_ORIENTATION = repmat({''}, size(sensorStruct.SENSOR));

         sensorStruct.PARAMETER = {'FLUORESCENCE_CHLA' 'TEMP_CPU_CHLA' 'BETA_BACKSCATTERING532' 'BETA_BACKSCATTERING880'};
         sensorStruct.PARAMETER_SENSOR = {'FLUOROMETER_CHLA' 'FLUOROMETER_CHLA' 'BACKSCATTERINGMETER_BBP532' 'BACKSCATTERINGMETER_BBP880'};
         sensorStruct.PARAMETER_DATA_MODE = repmat({'R'}, size(sensorStruct.PARAMETER));
         sensorStruct.PARAMETER_UNITS = repmat({''}, size(sensorStruct.PARAMETER));
         sensorStruct.PARAMETER_ACCURACY = repmat({''}, size(sensorStruct.PARAMETER));
         sensorStruct.PARAMETER_RESOLUTION = repmat({''}, size(sensorStruct.PARAMETER));

      elseif (any(strcmp('wlbb2fl_FL2sig', availableParam)) && ...
            any(strcmp('wlbb2fl_temp', availableParam)) && ...
            any(strcmp('wlbb2fl_BB1sig', availableParam)) && ...
            any(strcmp('wlbb2fl_BB2sig', availableParam)))

         egoVarNameList = {'FLUORESCENCE_CHLA' 'TEMP_CPU_CHLA' 'BETA_BACKSCATTERING470' 'BETA_BACKSCATTERING700'};
         gliderVarNameList = {'wlbb2fl_FL2sig' 'wlbb2fl_temp' 'wlbb2fl_BB1sig' 'wlbb2fl_BB2sig'};

         % retrieve existing sensor data
         sensorStructOld = get_sensor_struct_old(deployJsonData.glider_sensor, deployJsonDirName, gliderVarNameList);

         sensorStruct.SENSOR = {'FLUOROMETER_CHLA' 'BACKSCATTERINGMETER_BBP470' 'BACKSCATTERINGMETER_BBP700'};
         sensorStruct.SENSOR_MAKER = {'WETLABS' 'WETLABS' 'WETLABS'};
         sensorStruct.SENSOR_MODEL = {'ECO_FLBB2' 'ECO_FLBB2' 'ECO_FLBB2'};
         sensorStruct.SENSOR_SERIAL_NO = repmat({'9999'}, size(sensorStruct.SENSOR));
         sensorStruct.SENSOR_MOUNT = repmat({'MOUNTED_ON_GLIDER'}, size(sensorStruct.SENSOR));
         sensorStruct.SENSOR_ORIENTATION = repmat({''}, size(sensorStruct.SENSOR));

         sensorStruct.PARAMETER = {'FLUORESCENCE_CHLA' 'TEMP_CPU_CHLA' 'BETA_BACKSCATTERING470' 'BETA_BACKSCATTERING700'};
         sensorStruct.PARAMETER_SENSOR = {'FLUOROMETER_CHLA' 'FLUOROMETER_CHLA' 'BACKSCATTERINGMETER_BBP470' 'BACKSCATTERINGMETER_BBP700'};
         sensorStruct.PARAMETER_DATA_MODE = repmat({'R'}, size(sensorStruct.PARAMETER));
         sensorStruct.PARAMETER_UNITS = repmat({''}, size(sensorStruct.PARAMETER));
         sensorStruct.PARAMETER_ACCURACY = repmat({''}, size(sensorStruct.PARAMETER));
         sensorStruct.PARAMETER_RESOLUTION = repmat({''}, size(sensorStruct.PARAMETER));

      elseif (any(strcmp('eng_wlbb2fl_sig695nm', availableParam)) && ...
            any(strcmp('eng_wlbb2fl_temp', availableParam)) && ...
            any(strcmp('wlbb2fl_sig695nm_adjusted', availableParam)) && ...
            any(strcmp('eng_wlbb2fl_sig470nm', availableParam)) && ...
            any(strcmp('wlbb2fl_sig470nm_adjusted', availableParam)) && ...
            any(strcmp('eng_wlbb2fl_sig700nm', availableParam)) && ...
            any(strcmp('wlbb2fl_sig700nm_adjusted', availableParam)))

         egoVarNameList = {'FLUORESCENCE_CHLA' 'TEMP_CPU_CHLA' 'CHLA' 'BETA_BACKSCATTERING470' 'BBP470' 'BETA_BACKSCATTERING700' 'BBP700'};
         gliderVarNameList = {'eng_wlbb2fl_sig695nm' 'eng_wlbb2fl_temp' 'wlbb2fl_sig695nm_adjusted' 'eng_wlbb2fl_sig470nm' 'wlbb2fl_sig470nm_adjusted' 'eng_wlbb2fl_sig700nm' 'wlbb2fl_sig700nm_adjusted'};

         % retrieve existing sensor data
         sensorStructOld = get_sensor_struct_old(deployJsonData.glider_sensor, deployJsonDirName, gliderVarNameList);

         sensorStruct.SENSOR = {'FLUOROMETER_CHLA' 'BACKSCATTERINGMETER_BBP470' 'BACKSCATTERINGMETER_BBP700'};
         sensorStruct.SENSOR_MAKER = {'WETLABS' 'WETLABS' 'WETLABS'};
         sensorStruct.SENSOR_MODEL = {'ECO_FLBB2' 'ECO_FLBB2' 'ECO_FLBB2'};
         sensorStruct.SENSOR_SERIAL_NO = repmat({'9999'}, size(sensorStruct.SENSOR));
         sensorStruct.SENSOR_MOUNT = repmat({'MOUNTED_ON_GLIDER'}, size(sensorStruct.SENSOR));
         sensorStruct.SENSOR_ORIENTATION = repmat({''}, size(sensorStruct.SENSOR));

         sensorStruct.PARAMETER = {'FLUORESCENCE_CHLA' 'TEMP_CPU_CHLA' 'CHLA' 'BETA_BACKSCATTERING470' 'BBP470' 'BETA_BACKSCATTERING700' 'BBP700'};
         sensorStruct.PARAMETER_SENSOR = {'FLUOROMETER_CHLA' 'FLUOROMETER_CHLA' 'FLUOROMETER_CHLA' 'BACKSCATTERINGMETER_BBP470' 'BACKSCATTERINGMETER_BBP470' 'BACKSCATTERINGMETER_BBP700' 'BACKSCATTERINGMETER_BBP700'};
         sensorStruct.PARAMETER_DATA_MODE = repmat({'R'}, size(sensorStruct.PARAMETER));
         sensorStruct.PARAMETER_UNITS = repmat({''}, size(sensorStruct.PARAMETER));
         sensorStruct.PARAMETER_ACCURACY = repmat({''}, size(sensorStruct.PARAMETER));
         sensorStruct.PARAMETER_RESOLUTION = repmat({''}, size(sensorStruct.PARAMETER));
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

         sensorStruct.CALIBRATION_COEFFICIENT = [];
         if (any(strcmp('sg_cal_WETLabsCalData_wlbb2fl_Chlorophyll_scaleFactor', availableCoef)) || ...
               any(strcmp('sg_cal_WETLabsCalData_wlbb2fl_Chlorophyll_darkCounts', availableCoef)))
            FLUOROMETER_CHLA = [];
            FLUOROMETER_CHLA.ScaleFactCHLA = '<nc.data.sg_cal_WETLabsCalData_wlbb2fl_Chlorophyll_scaleFactor>';
            FLUOROMETER_CHLA.DarkCountCHLA = '<nc.data.sg_cal_WETLabsCalData_wlbb2fl_Chlorophyll_darkCounts>';
            sensorStruct.CALIBRATION_COEFFICIENT.FLUOROMETER_CHLA = FLUOROMETER_CHLA;

            sensorStruct.PARAMETER{end+1} = 'CHLA';
            sensorStruct.PARAMETER_SENSOR{end+1} = 'FLUOROMETER_CHLA';
            sensorStruct.PARAMETER_DATA_MODE{end+1} = 'R';
            sensorStruct.PARAMETER_UNITS{end+1} = '';
            sensorStruct.PARAMETER_ACCURACY{end+1} = '';
            sensorStruct.PARAMETER_RESOLUTION{end+1} = '';

            paramStructList(end+1) = get_param_struct;
            paramStructList(end).ego_variable_name = 'CHLA';
            paramStructList(end).derivation_comment = 'Not measured by the glider. Calculated by Coriolis';
         elseif (any(strcmp('sg_cal_wlbb2fl_sig695nm_scale_factor', availableCoef)) || ...
               any(strcmp('sg_cal_wlbb2fl_sig700nm_dark_counts', availableCoef)))
            FLUOROMETER_CHLA = [];
            FLUOROMETER_CHLA.ScaleFactCHLA = '<nc.data.sg_cal_wlbb2fl_sig695nm_scale_factor>';
            FLUOROMETER_CHLA.DarkCountCHLA = '<nc.data.sg_cal_wlbb2fl_sig700nm_dark_counts>';
            sensorStruct.CALIBRATION_COEFFICIENT.FLUOROMETER_CHLA = FLUOROMETER_CHLA;

            sensorStruct.PARAMETER{end+1} = 'CHLA2';
            sensorStruct.PARAMETER_SENSOR{end+1} = 'FLUOROMETER_CHLA';
            sensorStruct.PARAMETER_DATA_MODE{end+1} = 'R';
            sensorStruct.PARAMETER_UNITS{end+1} = '';
            sensorStruct.PARAMETER_ACCURACY{end+1} = '';
            sensorStruct.PARAMETER_RESOLUTION{end+1} = '';

            paramStructList(end+1) = get_param_struct;
            paramStructList(end).ego_variable_name = 'CHLA2';
            paramStructList(end).derivation_comment = 'Not measured by the glider. Calculated by Coriolis';
         end
         if (any(strcmp('sg_cal_WETLabsCalData_wlbb2fl_Scatter470_scaleFactor', availableCoef)) || ...
               any(strcmp('sg_cal_WETLabsCalData_wlbb2fl_Scatter470_darkCounts', availableCoef)))
            BACKSCATTERINGMETER_BBP470 = [];
            BACKSCATTERINGMETER_BBP470.ScaleFactBBP470 = '<nc.data.sg_cal_WETLabsCalData_wlbb2fl_Scatter470_scaleFactor>';
            BACKSCATTERINGMETER_BBP470.DarkCountBBP470 = '<nc.data.sg_cal_WETLabsCalData_wlbb2fl_Scatter470_darkCounts>';
            BACKSCATTERINGMETER_BBP470.KhiCoefBBP470 = 1.076;
            BACKSCATTERINGMETER_BBP470.MeasAngleBBP470 = 124;
            sensorStruct.CALIBRATION_COEFFICIENT.BACKSCATTERINGMETER_BBP470 = BACKSCATTERINGMETER_BBP470;

            sensorStruct.PARAMETER{end+1} = 'BBP470';
            sensorStruct.PARAMETER_SENSOR{end+1} = 'BACKSCATTERINGMETER_BBP470';
            sensorStruct.PARAMETER_DATA_MODE{end+1} = 'R';
            sensorStruct.PARAMETER_UNITS{end+1} = '';
            sensorStruct.PARAMETER_ACCURACY{end+1} = '';
            sensorStruct.PARAMETER_RESOLUTION{end+1} = '';

            paramStructList(end+1) = get_param_struct;
            paramStructList(end).ego_variable_name = 'BBP470';
            paramStructList(end).derivation_comment = 'Not measured by the glider. Calculated by Coriolis';
         elseif (any(strcmp('sg_cal_wlbb2fl_sig470nm_scale_factor', availableCoef)) || ...
               any(strcmp('sg_cal_wlbb2fl_sig470nm_dark_counts', availableCoef)))
            BACKSCATTERINGMETER_BBP470 = [];
            BACKSCATTERINGMETER_BBP470.ScaleFactBBP470 = '<nc.data.sg_cal_wlbb2fl_sig470nm_scale_factor>';
            BACKSCATTERINGMETER_BBP470.DarkCountBBP470 = '<nc.data.sg_cal_wlbb2fl_sig470nm_dark_counts>';
            BACKSCATTERINGMETER_BBP470.KhiCoefBBP470 = 1.076;
            BACKSCATTERINGMETER_BBP470.MeasAngleBBP470 = 124;
            sensorStruct.CALIBRATION_COEFFICIENT.BACKSCATTERINGMETER_BBP470 = BACKSCATTERINGMETER_BBP470;

            sensorStruct.PARAMETER{end+1} = 'BBP470_2';
            sensorStruct.PARAMETER_SENSOR{end+1} = 'BACKSCATTERINGMETER_BBP470';
            sensorStruct.PARAMETER_DATA_MODE{end+1} = 'R';
            sensorStruct.PARAMETER_UNITS{end+1} = '';
            sensorStruct.PARAMETER_ACCURACY{end+1} = '';
            sensorStruct.PARAMETER_RESOLUTION{end+1} = '';

            paramStructList(end+1) = get_param_struct;
            paramStructList(end).ego_variable_name = 'BBP470_2';
            paramStructList(end).derivation_comment = 'Not measured by the glider. Calculated by Coriolis';
         end
         if (any(strcmp('sg_cal_WETLabsCalData_wlbb2fl_Scatter532_scaleFactor', availableCoef)) || ...
               any(strcmp('sg_cal_WETLabsCalData_wlbb2fl_Scatter532_darkCounts', availableCoef)))
            BACKSCATTERINGMETER_BBP532 = [];
            BACKSCATTERINGMETER_BBP532.ScaleFactBBP532 = '<nc.data.sg_cal_WETLabsCalData_wlbb2fl_Scatter532_scaleFactor>';
            BACKSCATTERINGMETER_BBP532.DarkCountBBP532 = '<nc.data.sg_cal_WETLabsCalData_wlbb2fl_Scatter532_darkCounts>';
            BACKSCATTERINGMETER_BBP532.KhiCoefBBP532 = 1.076;
            BACKSCATTERINGMETER_BBP532.MeasAngleBBP532 = 124;
            sensorStruct.CALIBRATION_COEFFICIENT.BACKSCATTERINGMETER_BBP532 = BACKSCATTERINGMETER_BBP532;

            sensorStruct.PARAMETER{end+1} = 'BBP532';
            sensorStruct.PARAMETER_SENSOR{end+1} = 'BACKSCATTERINGMETER_BBP532';
            sensorStruct.PARAMETER_DATA_MODE{end+1} = 'R';
            sensorStruct.PARAMETER_UNITS{end+1} = '';
            sensorStruct.PARAMETER_ACCURACY{end+1} = '';
            sensorStruct.PARAMETER_RESOLUTION{end+1} = '';

            paramStructList(end+1) = get_param_struct;
            paramStructList(end).ego_variable_name = 'BBP532';
            paramStructList(end).derivation_comment = 'Not measured by the glider. Calculated by Coriolis';
         end
         if (any(strcmp('sg_cal_wlbb2fl_sig700nm_scale_factor', availableCoef)) || ...
               any(strcmp('sg_cal_wlbb2fl_sig700nm_dark_counts', availableCoef)))
            BACKSCATTERINGMETER_BBP700 = [];
            BACKSCATTERINGMETER_BBP700.ScaleFactBBP700 = '<nc.data.sg_cal_wlbb2fl_sig700nm_scale_factor>';
            BACKSCATTERINGMETER_BBP700.DarkCountBBP700 = '<nc.data.sg_cal_wlbb2fl_sig700nm_dark_counts>';
            BACKSCATTERINGMETER_BBP700.KhiCoefBBP700 = 1.076;
            BACKSCATTERINGMETER_BBP700.MeasAngleBBP700 = 124;
            sensorStruct.CALIBRATION_COEFFICIENT.BACKSCATTERINGMETER_BBP700 = BACKSCATTERINGMETER_BBP700;

            sensorStruct.PARAMETER{end+1} = 'BBP700_2';
            sensorStruct.PARAMETER_SENSOR{end+1} = 'BACKSCATTERINGMETER_BBP700';
            sensorStruct.PARAMETER_DATA_MODE{end+1} = 'R';
            sensorStruct.PARAMETER_UNITS{end+1} = '';
            sensorStruct.PARAMETER_ACCURACY{end+1} = '';
            sensorStruct.PARAMETER_RESOLUTION{end+1} = '';

            paramStructList(end+1) = get_param_struct;
            paramStructList(end).ego_variable_name = 'BBP700_2';
            paramStructList(end).derivation_comment = 'Not measured by the glider. Calculated by Coriolis';
         elseif (any(strcmp('sg_cal_WETLabsCalData_wlbb2fl_Scatter700_scaleFactor', availableCoef)) || ...
               any(strcmp('sg_cal_WETLabsCalData_wlbb2fl_Scatter700_darkCounts', availableCoef)))
            BACKSCATTERINGMETER_BBP700 = [];
            BACKSCATTERINGMETER_BBP700.ScaleFactBBP700 = '<nc.data.sg_cal_WETLabsCalData_wlbb2fl_Scatter700_scaleFactor>';
            BACKSCATTERINGMETER_BBP700.DarkCountBBP700 = '<nc.data.sg_cal_WETLabsCalData_wlbb2fl_Scatter700_darkCounts>';
            BACKSCATTERINGMETER_BBP700.KhiCoefBBP700 = 1.076;
            BACKSCATTERINGMETER_BBP700.MeasAngleBBP700 = 124;
            sensorStruct.CALIBRATION_COEFFICIENT.BACKSCATTERINGMETER_BBP700 = BACKSCATTERINGMETER_BBP700;

            sensorStruct.PARAMETER{end+1} = 'BBP700';
            sensorStruct.PARAMETER_SENSOR{end+1} = 'BACKSCATTERINGMETER_BBP700';
            sensorStruct.PARAMETER_DATA_MODE{end+1} = 'R';
            sensorStruct.PARAMETER_UNITS{end+1} = '';
            sensorStruct.PARAMETER_ACCURACY{end+1} = '';
            sensorStruct.PARAMETER_RESOLUTION{end+1} = '';

            paramStructList(end+1) = get_param_struct;
            paramStructList(end).ego_variable_name = 'BBP700';
            paramStructList(end).derivation_comment = 'Not measured by the glider. Calculated by Coriolis';
         end
         if (any(strcmp('sg_cal_WETLabsCalData_wlbb2fl_Scatter880_scaleFactor', availableCoef)) || ...
               any(strcmp('sg_cal_WETLabsCalData_wlbb2fl_Scatter880_darkCounts', availableCoef)))
            BACKSCATTERINGMETER_BBP880 = [];
            BACKSCATTERINGMETER_BBP880.ScaleFactBBP880 = '<nc.data.sg_cal_WETLabsCalData_wlbb2fl_Scatter880_scaleFactor>';
            BACKSCATTERINGMETER_BBP880.DarkCountBBP880 = '<nc.data.sg_cal_WETLabsCalData_wlbb2fl_Scatter880_darkCounts>';
            BACKSCATTERINGMETER_BBP880.KhiCoefBBP880 = 1.076;
            BACKSCATTERINGMETER_BBP880.MeasAngleBBP880 = 124;
            sensorStruct.CALIBRATION_COEFFICIENT.BACKSCATTERINGMETER_BBP880 = BACKSCATTERINGMETER_BBP880;

            sensorStruct.PARAMETER{end+1} = 'BBP880';
            sensorStruct.PARAMETER_SENSOR{end+1} = 'BACKSCATTERINGMETER_BBP880';
            sensorStruct.PARAMETER_DATA_MODE{end+1} = 'R';
            sensorStruct.PARAMETER_UNITS{end+1} = '';
            sensorStruct.PARAMETER_ACCURACY{end+1} = '';
            sensorStruct.PARAMETER_RESOLUTION{end+1} = '';

            paramStructList(end+1) = get_param_struct;
            paramStructList(end).ego_variable_name = 'BBP880';
            paramStructList(end).derivation_comment = 'Not measured by the glider. Calculated by Coriolis';
         end

         sensorStruct.parametersList = paramStructList;

         % update sensor data structure with existing sensor json file
         sensorStruct = update_sensor_data(sensorStruct, sensorStructOld, a_deploymentDirName, 'BB2FL', a_csvFid);

         % generate sensor json file
         outputFileName = [a_deploymentDirName '_ECO_FLBB2_' sensorStruct.SENSOR_SERIAL_NO{1} '.json'];
         outputFilePathName = [outputDirName outputFileName];
         sensorFileNameList{end+1} = outputFileName;

         ok = write_json_sensor_file(outputFilePathName, sensorStruct);
         if (ok == 0)
            fprintf('ERROR: Error while generating sensor JSON file: %s\n', outputFilePathName);
         end
      end

   case {'bpo'}

      %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
      % CTD

      sensorStructOld = [];
      gliderVarNameList = [];
      if (any(strcmp('Pressure_bin', availableParam)) && ...
            any(strcmp('TempC_LagCor_bin', availableParam)) && ...
            any(strcmp('Cond_LagCor_bin', availableParam)) && ...
            any(strcmp('Salinity_bin', availableParam)))

         gliderVarNameList = {'Pressure_bin' 'TempC_LagCor_bin' 'Cond_LagCor_bin' 'Salinity_bin'};

         % retrieve existing sensor data
         sensorStructOld = get_sensor_struct_old(deployJsonData.glider_sensor, deployJsonDirName, gliderVarNameList);

      elseif (any(strcmp('depth_bin', availableParam)) && ...
            any(strcmp('temperature_bin', availableParam)) && ...
            any(strcmp('conductivity_bin', availableParam)) && ...
            any(strcmp('salinity_bin', availableParam)))

         gliderVarNameList = {'depth_bin' 'temperature_bin' 'conductivity_bin' 'salinity_bin'};

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
         sensorStruct.PARAMETER_DATA_MODE = repmat({'R'}, size(sensorStruct.PARAMETER));
         sensorStruct.PARAMETER_UNITS = repmat({''}, size(sensorStruct.PARAMETER));
         sensorStruct.PARAMETER_ACCURACY = repmat({''}, size(sensorStruct.PARAMETER));
         sensorStruct.PARAMETER_RESOLUTION = repmat({''}, size(sensorStruct.PARAMETER));

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

   case {'pro'}

      %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
      % CTD

      sensorStructOld = [];
      gliderVarNameList = [];
      if (any(strcmp('Pressure_v', availableParam)) && ...
            any(strcmp('TempC_LagCor_v', availableParam)) && ...
            any(strcmp('Cond_LagCor_v', availableParam)) && ...
            any(strcmp('Salinity_v', availableParam)))

         gliderVarNameList = {'Pressure_v' 'TempC_LagCor_v' 'Cond_LagCor_v' 'Salinity_v'};

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
         sensorStruct.PARAMETER_DATA_MODE = repmat({'R'}, size(sensorStruct.PARAMETER));
         sensorStruct.PARAMETER_UNITS = repmat({''}, size(sensorStruct.PARAMETER));
         sensorStruct.PARAMETER_ACCURACY = repmat({''}, size(sensorStruct.PARAMETER));
         sensorStruct.PARAMETER_RESOLUTION = repmat({''}, size(sensorStruct.PARAMETER));

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

   case {'eng'}

      %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
      % CTD

      sensorStructOld = [];
      gliderVarNameList = [];
      if (any(strcmp('gpctd_Pressure', availableParam)) && ...
            any(strcmp('gpctd_Temp', availableParam)) && ...
            any(strcmp('gpctd_Cond', availableParam)))

         gliderVarNameList = {'gpctd_Pressure' 'gpctd_Temp' 'gpctd_Cond' ''};

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
         sensorStruct.PARAMETER_DATA_MODE = repmat({'R'}, size(sensorStruct.PARAMETER));
         sensorStruct.PARAMETER_UNITS = repmat({''}, size(sensorStruct.PARAMETER));
         sensorStruct.PARAMETER_ACCURACY = repmat({''}, size(sensorStruct.PARAMETER));
         sensorStruct.PARAMETER_RESOLUTION = repmat({''}, size(sensorStruct.PARAMETER));

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
      % DOXY

      sensorStruct = get_sensor_struct;
      sensorStructOld = [];
      gliderVarNameList = [];
      if (any(strcmp('aa1_TCPhase', availableParam)) && ...
            any(strcmp('aa1_Temp', availableParam)) && ...
            any(strcmp('aa1_O2', availableParam)))

         egoVarNameList = {'TPHASE_DOXY' 'TEMP_DOXY' 'MOLAR_DOXY'};
         gliderVarNameList = {'aa1_TCPhase' 'aa1_Temp' 'aa1_O2'};

         % retrieve existing sensor data
         sensorStructOld = get_sensor_struct_old(deployJsonData.glider_sensor, deployJsonDirName, gliderVarNameList);

         sensorStruct.SENSOR = {'OPTODE_DOXY'};
         sensorStruct.SENSOR_MAKER = {'AANDERAA'};
         sensorStruct.SENSOR_MODEL = {'AANDERAA_OPTODE_4330'};
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
         OPTODE_DOXY = [];
         OPTODE_DOXY.Case = '201_201_301';
         OPTODE_DOXY.DoxyCalibRefSalinity = 0;
         sensorStruct.CALIBRATION_COEFFICIENT.OPTODE_DOXY = OPTODE_DOXY;

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

      %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
      % FLBB2

      sensorStruct = get_sensor_struct;
      sensorStructOld = [];
      gliderVarNameList = [];

      if (any(strcmp('wl1_Chlsig1', availableParam)) && ...
            any(strcmp('wl1_temp1', availableParam)) && ...
            any(strcmp('wl1_sig1', availableParam)) && ...
            any(strcmp('wl1_sig2', availableParam)))

         egoVarNameList = {'CHLA' 'TEMP_CPU_CHLA' 'BBP470' 'BBP700'};
         gliderVarNameList = {'wl1_Chlsig1' 'wl1_temp1' 'wl1_sig1' 'wl1_sig2'};

         % retrieve existing sensor data
         sensorStructOld = get_sensor_struct_old(deployJsonData.glider_sensor, deployJsonDirName, gliderVarNameList);

         sensorStruct.SENSOR = {'FLUOROMETER_CHLA' 'BACKSCATTERINGMETER_BBP470' 'BACKSCATTERINGMETER_BBP700'};
         sensorStruct.SENSOR_MAKER = {'WETLABS' 'WETLABS' 'WETLABS'};
         sensorStruct.SENSOR_MODEL = {'ECO_FLBB2' 'ECO_FLBB2' 'ECO_FLBB2'};
         sensorStruct.SENSOR_SERIAL_NO = repmat({'9999'}, size(sensorStruct.SENSOR));
         sensorStruct.SENSOR_MOUNT = repmat({'MOUNTED_ON_GLIDER'}, size(sensorStruct.SENSOR));
         sensorStruct.SENSOR_ORIENTATION = repmat({''}, size(sensorStruct.SENSOR));

         sensorStruct.PARAMETER = {'CHLA' 'TEMP_CPU_CHLA' 'BBP470' 'BBP700'};
         sensorStruct.PARAMETER_SENSOR = {'FLUOROMETER_CHLA' 'FLUOROMETER_CHLA' 'BACKSCATTERINGMETER_BBP470' 'BACKSCATTERINGMETER_BBP700'};
         sensorStruct.PARAMETER_DATA_MODE = repmat({'R'}, size(sensorStruct.PARAMETER));
         sensorStruct.PARAMETER_UNITS = repmat({''}, size(sensorStruct.PARAMETER));
         sensorStruct.PARAMETER_ACCURACY = repmat({''}, size(sensorStruct.PARAMETER));
         sensorStruct.PARAMETER_RESOLUTION = repmat({''}, size(sensorStruct.PARAMETER));
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
         sensorStruct = update_sensor_data(sensorStruct, sensorStructOld, a_deploymentDirName, 'BB2FL', a_csvFid);

         % generate sensor json file
         outputFileName = [a_deploymentDirName '_ECO_FLBB2_' sensorStruct.SENSOR_SERIAL_NO{1} '.json'];
         outputFilePathName = [outputDirName outputFileName];
         sensorFileNameList{end+1} = outputFileName;

         ok = write_json_sensor_file(outputFilePathName, sensorStruct);
         if (ok == 0)
            fprintf('ERROR: Error while generating sensor JSON file: %s\n', outputFilePathName);
         end
      end

   otherwise
      fprintf('ERROR: data type ''%s'' not managed\n', dataType);

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
%   11/30/2023 - RNU - creation
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
      if (~strcmp(a_sensorStruct.parametersList(idF1).glider_variable_name, a_sensorStructOld.parametersList(idF2).glider_variable_name))
         fprintf(a_csvFid, 'WARNING; %s; %s; PARAMETER; %s; glider_variable_name NOT updated;%s;%s\n', ...
            a_deployName, a_sensorLabel, paramName, ...
            a_sensorStruct.parametersList(idF1).glider_variable_name, a_sensorStructOld.parametersList(idF2).glider_variable_name);
         % o_sensorStruct.parametersList(idF1).glider_variable_name = a_sensorStructOld.parametersList(idF2).glider_variable_name;
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
         if (~strcmp(a_sensorStructOld.parametersList(idF2).derivation_equation, 'Not measured by the glider. Calculated by Coriolis'))
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
         fprintf(a_csvFid, 'WARNING; %s; %s; PARAMETER; %s; processing_id NOT updated;%s;%s\n', ...
            a_deployName, a_sensorLabel, paramName, ...
            a_sensorStruct.parametersList(idF1).processing_id, a_sensorStructOld.parametersList(idF2).processing_id);
         % o_sensorStruct.parametersList(idF1).processing_id = a_sensorStructOld.parametersList(idF2).processing_id;
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
%   11/30/2023 - RNU - creation
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
   {'glider_adjusted_variable_name'}, ...
   {'comment'}, ...
   {'cell_methods'}, ...
   {'reference_scale'}, ...
   {'derivation_equation'}, ...
   {'derivation_coefficient'}, ...
   {'derivation_comment'}, ...
   {'derivation_date'}, ...
   {'processing_id'}, ...
   ];
tabs = [{'\t\t\t\t'} {'\t\t\t'} {'\t'} {'\t\t\t\t\t\t'} {'\t\t\t\t\t'} {'\t\t\t\t'} {'\t\t\t'} {'\t\t'} {'\t\t\t'} {'\t\t\t\t'} {'\t\t\t\t\t'}];
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
      if (ismember(idF, [6 10]))
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
%   11/30/2023 - RNU - creation
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
%   11/30/2023 - RNU - creation
% ------------------------------------------------------------------------------
function o_paramStruct = get_param_struct

o_paramStruct = struct( ...
   'ego_variable_name', '', ...
   'glider_variable_name', '', ...
   'glider_adjusted_variable_name', '', ...
   'comment', '', ...
   'cell_methods', '', ...
   'reference_scale', '', ...
   'derivation_equation', '', ...
   'derivation_coefficient', '', ...
   'derivation_comment', '', ...
   'derivation_date', '', ...
   'processing_id', '');

return
