% ------------------------------------------------------------------------------
% Compare JSON sensor files information.
%
% SYNTAX :
%   gl_compare_sensor_json_file or
%   gl_compare_sensor_json_file('data', 'crate_mooset00_38')
%
% INPUT PARAMETERS :
%   varargin : input arguments
%      must be provided in pairs i.e. ('argument_name', 'argument_value')
%      expected argument names:
%      'data' : identify the deployment (i.e. the sub-directory of the
%               JSON_DIRECTORY_1 directory) to process
%      if no argument is provided: all the deployments of the
%      JSON_DIRECTORY_1 directory are processed
%
% OUTPUT PARAMETERS :
%
% EXAMPLES :
%
% SEE ALSO :
% AUTHOR : Jean-Philippe Rannou (Capgemini) (jean.philippe.rannou@partenaire-exterieur.ifremer.fr)
% ------------------------------------------------------------------------------
% RELEASES :
%   12/05/2023 - RNU - creation
% ------------------------------------------------------------------------------
function gl_compare_sensor_json_file(varargin)

% top directory of the deployment directories
JSON_DIRECTORY_1 = 'C:\Users\jprannou\_DATA\GLIDER\slocum\';
%JSON_DIRECTORY_1 = 'C:\Users\jprannou\_DATA\GLIDER\seaglider\';
% JSON_DIRECTORY_1 = 'C:\Users\jprannou\_DATA\GLIDER\seaexplorer\';
JSON_DIRECTORY_2 = 'C:\Users\jprannou\_DATA\GLIDER\out\';

% directory to store the log file
DIR_LOG_FILE = 'C:\Users\jprannou\_RNU\Glider\work\log\';

% directory to store the CSV file
DIR_CSV_FILE = 'C:\Users\jprannou\_RNU\Glider\work\csv\';

% default values initialization
gl_init_default_values;


% check configuration information
if ~(exist(JSON_DIRECTORY_1, 'dir') == 7)
   fprintf('ERROR: ''JSON_DIRECTORY_1'' directory not found: %s\n', DATA_DIRECTORY);
   return
end

if ~(exist(JSON_DIRECTORY_2, 'dir') == 7)
   fprintf('ERROR: ''JSON_DIRECTORY_2'' directory not found: %s\n', DATA_DIRECTORY);
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
            if (exist([JSON_DIRECTORY_1 '/' varargin{id+1}], 'dir'))
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
logFile = [DIR_LOG_FILE '/' 'gl_compare_sensor_json_file_' deploymentDir '_' datestr(now, 'yyyymmddTHHMMSS') '.log'];
diary(logFile);
tic;

% create the CSV output file
outputFileName = [DIR_CSV_FILE '/' 'gl_compare_sensor_json_file_' deploymentDir '_' datestr(now, 'yyyymmddTHHMMSS') '.csv'];
fidOut = fopen(outputFileName, 'wt');
if (fidOut == -1)
   return
end
header = 'DEPLOYMENT;JSON FILE DIR 1;JSON FILE DIR 2;;;;;DIR 1;DIR 2';
fprintf(fidOut, '%s\n', header);

% check glider deployment
if (isempty(deploymentDir))
   % check all the deployments of the DATA_DIRECTORY directory
   dirInfo = dir(JSON_DIRECTORY_1);
   for dirNum = 1:length(dirInfo)
      if ~(strcmp(dirInfo(dirNum).name, '.') || strcmp(dirInfo(dirNum).name, '..'))
         dirName = dirInfo(dirNum).name;
         
         compare_sensor_json_file(JSON_DIRECTORY_1, JSON_DIRECTORY_2, dirName, fidOut);
      end
   end
else
   % check the data of this deployment
   compare_sensor_json_file(JSON_DIRECTORY_1, JSON_DIRECTORY_2, deploymentDir, fidOut);
end

fclose(fidOut);

ellapsedTime = toc;
fprintf('done (Elapsed time is %.1f seconds)\n', ellapsedTime);

diary off;

return

% ------------------------------------------------------------------------------
% Compare JSON sensor files information for a given deployment.
%
% SYNTAX :
% compare_sensor_json_file(a_deploymentTopDirName1, a_deploymentTopDirName2, a_deploymentDirName, a_csvFid)
%
% INPUT PARAMETERS :
%   a_deploymentTopDirName : top directory of deployments directory
%   a_deploymentDirName    : directory of the deployment
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
%   12/05/2023 - RNU - creation
% ------------------------------------------------------------------------------
function compare_sensor_json_file(a_deploymentTopDirName1, a_deploymentTopDirName2, a_deploymentDirName, a_csvFid)

fprintf('Processing deployment: %s\n', a_deploymentDirName);

% retrieve JSON sensor file information
[paramListStruct1, calCoefListStruct1] = get_link_to_data(a_deploymentTopDirName1, a_deploymentDirName);
[paramListStruct2, calCoefListStruct2] = get_link_to_data(a_deploymentTopDirName2, a_deploymentDirName);

if (isempty(paramListStruct1) || isempty(paramListStruct2))
   if (isempty(paramListStruct1))
      fprintf(a_csvFid, '%s;;;EMPTY_IN_DIR_1\n', a_deploymentDirName);
   end
   if (isempty(paramListStruct2))
      fprintf(a_csvFid, '%s;;;EMPTY_IN_DIR_2\n', a_deploymentDirName);
   end
   return
end

% compare parameter information 
egoVarNames1 = {paramListStruct1.ego_variable_name};
egoVarNames2 = {paramListStruct2.ego_variable_name};

egoVarNamesOnly1 = setdiff(egoVarNames1, egoVarNames2);
for idV = 1:length(egoVarNamesOnly1)
   idF = find(strcmp(egoVarNamesOnly1{idV}, egoVarNames1));
   fprintf(a_csvFid, '%s;%s;;PARAMETER;%s;ONLY_IN_DIR_1\n', ...
      a_deploymentDirName, paramListStruct1(idF).json_file, egoVarNamesOnly1{idV});
end
egoVarNamesOnly2 = setdiff(egoVarNames2, egoVarNames1);
for idV = 1:length(egoVarNamesOnly2)
   idF = find(strcmp(egoVarNamesOnly2{idV}, egoVarNames2));
   fprintf(a_csvFid, '%s;;%s;PARAMETER;%s;ONLY_IN_DIR_2\n', ...
      a_deploymentDirName, paramListStruct2(idF).json_file, egoVarNamesOnly2{idV});
end

egoVarNames = intersect(egoVarNames1, egoVarNames2, 'stable');
fieldNames = fields(paramListStruct1);
excludedFields = {'param_units' 'sensor_mount' 'sensor_orientation' 'json_file'};
for idV = 1:length(egoVarNames)
   egoVarName = egoVarNames{idV};
   idF1 = find(strcmp(egoVarName, egoVarNames1));
   idF2 = find(strcmp(egoVarName, egoVarNames2));
   paramStruct1 = paramListStruct1(idF1);
   paramStruct2 = paramListStruct2(idF2);

   for idF = 1:length(fieldNames)
      fieldName = fieldNames{idF};
      if (~ismember(fieldName, excludedFields))
         if (~strcmp(paramStruct1.(fieldName), paramStruct2.(fieldName)))
            fprintf(a_csvFid, '%s;%s;%s;PARAMETER;%s;%s;differ;"%s";"%s"\n', ...
               a_deploymentDirName, ...
               paramStruct1.json_file, paramStruct2.json_file, ...
               egoVarName, fieldName, ...
               paramStruct1.(fieldName), paramStruct2.(fieldName));
         end
      elseif (strcmp(fieldName, 'param_units'))
         if (~strcmp(paramStruct1.(fieldName), paramStruct2.(fieldName)) && ...
               (~isempty(paramStruct2.param_accuracy) || ~isempty(paramStruct2.param_resolution)))
            fprintf(a_csvFid, '%s;%s;%s;PARAMETER;%s;%s;differ;"%s";"%s"\n', ...
               a_deploymentDirName, ...
               paramStruct1.json_file, paramStruct2.json_file, ...
               egoVarName, fieldName, ...
               paramStruct1.(fieldName), paramStruct2.(fieldName));
         end
      end
   end
end

if (~isempty(calCoefListStruct1) && ~isempty(calCoefListStruct2))

   % compare calibration coefficient information
   calibCoefSensor1 = {calCoefListStruct1.sensor};
   calibCoefSensor2 = {calCoefListStruct2.sensor};

   calibCoefSensorOnly1 = setdiff(calibCoefSensor1, calibCoefSensor2);
   for idV = 1:length(calibCoefSensorOnly1)
      idF = find(strcmp(calibCoefSensorOnly1{idV}, calibCoefSensor1));
      fprintf(a_csvFid, '%s;%s;;CALIB_COEF;%s;ONLY_IN_DIR_1;%s;%s\n', ...
         a_deploymentDirName, calCoefListStruct1(idF).json_file, ...
         calibCoefSensorOnly1{idV}, calCoefListStruct1(idF).type, calCoefListStruct1(idF).value);
   end
   calibCoefSensorOnly2 = setdiff(calibCoefSensor2, calibCoefSensor1);
   for idV = 1:length(calibCoefSensorOnly2)
      idF = find(strcmp(calibCoefSensorOnly2{idV}, calibCoefSensor2));
      fprintf(a_csvFid, '%s;;%s;CALIB_COEF;%s;ONLY_IN_DIR_2;%s;%s\n', ...
         a_deploymentDirName, calCoefListStruct2(idF).json_file, ...
         calibCoefSensorOnly2{idV}, calCoefListStruct2(idF).type, calCoefListStruct2(idF).value);
   end

   calibCoefSensors = intersect(calibCoefSensor1, calibCoefSensor2, 'stable');
   fieldNames = fields(calCoefListStruct1);
   excludedFields = {'json_file'};
   for idV = 1:length(calibCoefSensors)
      calibCoefSensor = calibCoefSensors{idV};
      idF1 = find(strcmp(calibCoefSensor, calibCoefSensor1));
      idF2 = find(strcmp(calibCoefSensor, calibCoefSensor2));

      if ((length(idF1) > 1) || (length(idF2) > 1))
         calInfo1 = [];
         for idC = idF1
            calCoefStruct1 = calCoefListStruct1(idC);
            calInfo1 = [calInfo1; [{calCoefStruct1.type} {calCoefStruct1.value}]];
         end
         calInfo2 = [];
         for idC = idF2
            calCoefStruct2 = calCoefListStruct2(idC);
            calInfo2 = [calInfo2; [{calCoefStruct2.type} {calCoefStruct2.value}]];
         end
         calInfo = calInfo1;
         for idL = 1:size(calInfo2, 1)
            if ~(any(strcmp(calInfo(:, 1), calInfo2{idL, 1}) & strcmp(calInfo(:, 2), calInfo2{idL, 2})))
               calInfo = [calInfo; calInfo2(idL, :)];
            end
         end
         for idL = 1:size(calInfo, 1)
            idF21 = find(strcmp(calInfo{idL, 1}, calInfo1(:, 1)) & strcmp(calInfo{idL, 2}, calInfo1(:, 2)));
            idF22 = find(strcmp(calInfo{idL, 1}, calInfo2(:, 1)) & strcmp(calInfo{idL, 2}, calInfo2(:, 2)));

            if (~isempty(idF21) && ~isempty(idF22))
               calCoefStruct1 = calCoefListStruct1(idF1(idF21));
               calCoefStruct2 = calCoefListStruct2(idF2(idF22));

               for idF = 1:length(fieldNames)
                  fieldName = fieldNames{idF};
                  if (~ismember(fieldName, excludedFields))
                     if (~strcmp(calCoefStruct1.(fieldName), calCoefStruct2.(fieldName)))
                        fprintf(a_csvFid, '%s;%s;%s;CALIB_COEF;%s;%s;differ;%s;%s\n', ...
                           a_deploymentDirName, ...
                           calCoefStruct1.json_file, calCoefStruct2.json_file, ...
                           calCoefStruct1.sensor, fieldName, ...
                           calCoefStruct1.(fieldName), calCoefStruct2.(fieldName));
                     end
                  end
               end

            elseif (~isempty(idF21))

               calCoefStruct1 = calCoefListStruct1(idF1(idF21));
               fprintf(a_csvFid, '%s;%s;;CALIB_COEF;%s;ONLY_IN_DIR_1;%s;%s\n', ...
                  a_deploymentDirName, calCoefStruct1.json_file, ...
                  calCoefStruct1.sensor, calCoefStruct1.type, calCoefStruct1.value);

            elseif (~isempty(idF22))

               calCoefStruct2 = calCoefListStruct2(idF2(idF22));
               fprintf(a_csvFid, '%s;%s;;CALIB_COEF;%s;ONLY_IN_DIR_2;%s;%s\n', ...
                  a_deploymentDirName, calCoefStruct2.json_file, ...
                  calCoefStruct2.sensor, calCoefStruct2.type, calCoefStruct2.value);

            end
         end

      else

         calCoefStruct1 = calCoefListStruct1(idF1);
         calCoefStruct2 = calCoefListStruct2(idF2);

         for idF = 1:length(fieldNames)
            fieldName = fieldNames{idF};
            if (~ismember(fieldName, excludedFields))
               if (~strcmp(calCoefStruct1.(fieldName), calCoefStruct2.(fieldName)))
                  fprintf(a_csvFid, '%s;%s;%s;CALIB_COEF;%s;%s;differ;%s;%s\n', ...
                     a_deploymentDirName, ...
                     calCoefStruct1.json_file, calCoefStruct2.json_file, ...
                     calCoefStruct1.sensor, fieldName, ...
                     calCoefStruct1.(fieldName), calCoefStruct2.(fieldName));
               end
            end
         end
      end
   end

elseif (~isempty(calCoefListStruct1))

   calibCoefSensor1 = {calCoefListStruct1.sensor};
   for idV = 1:length(calibCoefSensor1)
      idF = find(strcmp(calibCoefSensor1{idV}, calibCoefSensor1));
      fprintf(a_csvFid, '%s;%s;;CALIB_COEF;%s;ONLY_IN_DIR_1;%s;%s\n', ...
         a_deploymentDirName, calCoefListStruct1(idF).json_file, ...
         calCoefListStruct1(idF).sensor, calCoefListStruct1(idF).type, calCoefListStruct1(idF).value);
   end

elseif (~isempty(calCoefListStruct2))

   calibCoefSensor2 = {calCoefListStruct2.sensor};
   for idV = 1:length(calibCoefSensor2)
      idF = find(strcmp(calibCoefSensor2{idV}, calibCoefSensor2));
      fprintf(a_csvFid, '%s;;%s;CALIB_COEF;%s;ONLY_IN_DIR_2;%s;%s\n', ...
         a_deploymentDirName, calCoefListStruct2(idF).json_file, ...
         calCoefListStruct2(idF).sensor, calCoefListStruct2(idF).type, calCoefListStruct2(idF).value);
   end
end

return

% ------------------------------------------------------------------------------
% Retrieve EGO to glider parameter link.
%
% SYNTAX :
% [o_paramListStruct, o_calCoefListStruct] = get_link_to_data(...
%   a_deploymentTopDirName, a_deploymentDirName)
%
% INPUT PARAMETERS :
%   a_deploymentTopDirName : top directory of deployments directory
%   a_deploymentDirName    : directory of the deployment
%
% OUTPUT PARAMETERS :
%   o_paramListStruct   : information on list of glider parameters
%   o_calCoefListStruct : information on list calibration coefficients
%
% EXAMPLES :
%
% SEE ALSO :
% AUTHOR : Jean-Philippe Rannou (Capgemini) (jean.philippe.rannou@partenaire-exterieur.ifremer.fr)
% ------------------------------------------------------------------------------
% RELEASES :
%   12/05/2023 - RNU - creation
% ------------------------------------------------------------------------------
function [o_paramListStruct, o_calCoefListStruct] = get_link_to_data(...
   a_deploymentTopDirName, a_deploymentDirName)

% output parameters initialization
o_paramListStruct = [];
o_calCoefListStruct = [];

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
         if (isfield(paramData, 'glider_adjusted_variable_name'))
            paramStruct.glider_adjusted_variable_name = paramData.glider_adjusted_variable_name;
         end
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

      calibCoef = sensorData.CALIBRATION_COEFFICIENT;
      if (~isempty(calibCoef))
         if (isstruct(calibCoef))
            fieldNames = fields(calibCoef);
            for idF = 1:length(fieldNames)
               fieldName = fieldNames{idF};
               calCoef = calibCoef.(fieldName);
               for idC = 1:length(calCoef)
                  if (iscell(calCoef))
                     coef = calCoef{idC};
                  else
                     coef = calCoef(idC);
                  end
                  fieldNames2 = fields(coef);
                  calStruct = [];
                  calStruct.sensor = fieldName;
                  calStruct.type = fieldNames2{1};
                  calStruct.value = coef.(fieldNames2{1});
                  calStruct.json_file = sensorFileNames{idFile};
                  o_calCoefListStruct = [o_calCoefListStruct calStruct];
               end
            end
         else
            for idC1 = 1:length(calibCoef)
               if (iscell(calibCoef))
                  calibCoef2 = calibCoef{idC1};
               else
                  calibCoef2 = calibCoef(idC1);
               end
               fieldNames = fields(calibCoef2);
               for idF = 1:length(fieldNames)
                  fieldName = fieldNames{idF};
                  calCoef = calibCoef2.(fieldName);
                  for idC = 1:length(calCoef)
                     if (iscell(calCoef))
                        coef = calCoef{idC};
                     else
                        coef = calCoef(idC);
                     end
                     fieldNames2 = fields(coef);
                     calStruct = [];
                     calStruct.sensor = fieldName;
                     calStruct.type = fieldNames2{1};
                     calStruct.value = coef.(fieldNames2{1});
                     calStruct.json_file = sensorFileNames{idFile};
                     o_calCoefListStruct = [o_calCoefListStruct calStruct];
                  end
               end
            end
         end
      end
   end
else
   fprintf('WARNING: directory not found: %s\n', jsonDirectory);
   return
end

return
