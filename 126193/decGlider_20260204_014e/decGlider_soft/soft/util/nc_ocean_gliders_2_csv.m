% ------------------------------------------------------------------------------
% Convert NetCDF OceanGliders file contents in CSV format.
% The default behaviour is :
%    - to process all the deployments (the directories) stored in the
%      DIR_INPUT_NC_FILES directory
% this behaviour can be modified by input arguments.
%
% SYNTAX :
%   nc_ocean_gliders_2_csv(varargin)
%
% INPUT PARAMETERS :
%   varargin : input arguments
%      must be provided in pairs i.e. ('argument_name', 'argument_value')
%      expected argument names:
%      'data' : identify the deployment (i.e. the sub-directory of the
%               DIR_INPUT_NC_FILES directory) to process
%
% OUTPUT PARAMETERS :
%
% EXAMPLES :
%
% SEE ALSO :
% AUTHOR : Jean-Philippe Rannou (Capgemini) (jean.philippe.rannou@partenaire-exterieur.ifremer.fr)
% ------------------------------------------------------------------------------
% RELEASES :
%   02/11/2025 - RNU - creation
% ------------------------------------------------------------------------------
function nc_ocean_gliders_2_csv(varargin)

% top directory of the deployment directories
DIR_INPUT_NC_FILES = 'C:\Users\jprannou\_DATA\GLIDER\FORMAT_1.5\';

% directory to store the log file
DIR_LOG_FILE = 'C:\Users\jprannou\_RNU\Glider\work\log\';

% default values initialization
gl_init_default_values;


% create and start log file recording
logFile = [DIR_LOG_FILE '/' 'nc_ocean_gliders_2_csv_' datestr(now, 'yyyymmddTHHMMSS') '.log'];
diary(logFile);
tic;

% check input arguments
dataToProcessDir = [];
if (nargin > 0)
   if (rem(nargin, 2) ~= 0)
      fprintf('ERROR: expecting an even number of input arguments (e.g. (''argument_name'', ''argument_value'') => exit\n');
      diary off;
      return
   else
      for id = 1:2:nargin
         if (strcmpi(varargin{id}, 'data'))
            if (exist([DIR_INPUT_NC_FILES '/' varargin{id+1}], 'dir'))
               dataToProcessDir = [DIR_INPUT_NC_FILES '/' varargin{id+1}];
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

% convert glider data
if (isempty(dataToProcessDir))
   % convert all the deployments of the DIR_INPUT_NC_FILES directory
   dirInfo = dir(DIR_INPUT_NC_FILES);
   for dirNum = 1:length(dirInfo)
      if ~(strcmp(dirInfo(dirNum).name, '.') || strcmp(dirInfo(dirNum).name, '..'))
         dirName = dirInfo(dirNum).name;

         nc_ocean_gliders_2_csv_file([DIR_INPUT_NC_FILES '/' dirName]);
      end
   end
else
   % convert the data of this deployment
   nc_ocean_gliders_2_csv_file(dataToProcessDir);
end

ellapsedTime = toc;
fprintf('done (Elapsed time is %.1f seconds)\n', ellapsedTime);

diary off;

return

% ------------------------------------------------------------------------------
% Convert the NetCDF OceanGliders file of a given directory in CSV format.
%
% SYNTAX :
%  nc_ocean_gliders_2_csv_file(a_dirName)
%
% INPUT PARAMETERS :
%   a_dirName : directory of the OceanGliders file
%
% OUTPUT PARAMETERS :
%
% EXAMPLES :
%
% SEE ALSO :
% AUTHOR : Jean-Philippe Rannou (Capgemini) (jean.philippe.rannou@partenaire-exterieur.ifremer.fr)
% ------------------------------------------------------------------------------
% RELEASES :
%   02/11/2025 - RNU - creation
% ------------------------------------------------------------------------------
function nc_ocean_gliders_2_csv_file(a_dirName)


ncFiles = dir([a_dirName '/*_*T*_*.nc']);
for idF = 1:length(ncFiles)
   ncFileName = ncFiles(idF).name;
   [~, name, ext] = fileparts(ncFileName);
   inputFilePathName = [a_dirName '/' name ext];
   outFilePathName = [a_dirName '/' name '.csv'];

   fprintf('Converting: %s to %s\n', inputFilePathName, outFilePathName);

   % read the OceanGliders file contents
   [dimensions, globalAttributes, trajNameData, platformInfoData, ...
      deployInfoData, fieldComparisonInfoData, hardwareInfoData, ...
      telecomInfoData, sensorInfoData, paramData] = ...
      gl_read_file_ocean_gliders(inputFilePathName);

   % create CSV file
   fidOut = fopen(outFilePathName, 'wt');
   if (fidOut == -1)
      fprintf('ERROR: Unable to create output file: %s\n', outFilePathName);
      return
   end

   fprintf(fidOut, '**********\n');
   fprintf(fidOut, 'DIMENSION\n');
   fprintf(fidOut, '**********\n');
   fprintf(fidOut, 'Dim. name; Dim. value\n');
   fprintf(fidOut, '-------\n');

   for id = 1:2:length(dimensions)
      if (~isempty(dimensions{id+1}))
         fprintf(fidOut, '%s; %d\n', dimensions{id}, dimensions{id+1});
      end
   end

   fprintf(fidOut, '******************\n');
   fprintf(fidOut, 'GLOBAL ATTRIBUTES\n');
   fprintf(fidOut, '******************\n');
   fprintf(fidOut, 'Att. name; Att. value\n');
   fprintf(fidOut, '-------\n');

   floatWmo = gl_get_data_from_name('WMO_IDENTIFIER', globalAttributes);
   if (isempty(floatWmo))
      floatWmo = 9999999;
   else
      floatWmo = str2num(floatWmo);
   end
   for id = 1:2:length(globalAttributes)
      fprintf(fidOut, '%s; %s\n', globalAttributes{id}, globalAttributes{id+1});
   end

   fprintf(fidOut, '*****************\n');
   fprintf(fidOut, 'TRAJECTORY NAME\n');
   fprintf(fidOut, '*****************\n');
   fprintf(fidOut, 'Variable name; Variable value\n');
   fprintf(fidOut, '-------\n');

   for id = 1:2:length(trajNameData)
      if (isstring(trajNameData{id+1}))
         valueStr = trajNameData{id+1};
      else
         valueStr = sprintf('%g', trajNameData{id+1});
      end
      fprintf(fidOut, '%s; %s\n', trajNameData{id}, valueStr);
   end

   fprintf(fidOut, '***********************\n');
   fprintf(fidOut, 'PLATFORM INFORMATION\n');
   fprintf(fidOut, '***********************\n');
   fprintf(fidOut, 'Variable name; Variable value\n');
   fprintf(fidOut, '-------\n');

   for id = 1:2:length(platformInfoData)
      if (isstring(platformInfoData{id+1}))
         valueStr = platformInfoData{id+1};
      else
         valueStr = sprintf('%g', platformInfoData{id+1});
      end
      fprintf(fidOut, '%s; %s\n', platformInfoData{id}, valueStr);
   end

   fprintf(fidOut, '*************************\n');
   fprintf(fidOut, 'DEPLOYMENT INFORMATION\n');
   fprintf(fidOut, '*************************\n');
   fprintf(fidOut, 'Variable name; Variable value\n');
   fprintf(fidOut, '-------\n');

   for id = 1:2:length(deployInfoData)
      if (isstring(deployInfoData{id+1}))
         valueStr = deployInfoData{id+1};
      else
         valueStr = sprintf('%g', deployInfoData{id+1});
      end
      fprintf(fidOut, '%s; %s\n', deployInfoData{id}, valueStr);
   end

   fprintf(fidOut, '*******************************\n');
   fprintf(fidOut, 'FIELD COMPARISON INFORMATION\n');
   fprintf(fidOut, '*******************************\n');
   fprintf(fidOut, 'Variable name; Variable value\n');
   fprintf(fidOut, '-------\n');

   for id = 1:2:length(fieldComparisonInfoData)
      if (isstring(fieldComparisonInfoData{id+1}))
         valueStr = fieldComparisonInfoData{id+1};
      else
         valueStr = sprintf('%g', fieldComparisonInfoData{id+1});
      end
      fprintf(fidOut, '%s; %s\n', fieldComparisonInfoData{id}, valueStr);
   end

   fprintf(fidOut, '************************\n');
   fprintf(fidOut, 'HARDWARE INFORMATION\n');
   fprintf(fidOut, '************************\n');
   fprintf(fidOut, 'Variable name; Variable value\n');
   fprintf(fidOut, '-------\n');

   for id = 1:2:length(hardwareInfoData)
      if (isstring(hardwareInfoData{id+1}))
         valueStr = hardwareInfoData{id+1};
      else
         valueStr = sprintf('%g', hardwareInfoData{id+1});
      end
      fprintf(fidOut, '%s; %s\n', hardwareInfoData{id}, valueStr);
   end

   fprintf(fidOut, '**********************\n');
   fprintf(fidOut, 'TELECOM INFORMATION\n');
   fprintf(fidOut, '**********************\n');
   fprintf(fidOut, 'Variable name; Variable value\n');
   fprintf(fidOut, '-------\n');

   for id = 1:2:length(telecomInfoData)
      if (isstring(telecomInfoData{id+1}))
         valueStr = telecomInfoData{id+1};
      else
         valueStr = sprintf('%g', telecomInfoData{id+1});
      end
      fprintf(fidOut, '%s; %s\n', telecomInfoData{id}, valueStr);
   end

   fprintf(fidOut, '********************\n');
   fprintf(fidOut, 'SENSOR INFORMATION\n');
   fprintf(fidOut, '********************\n');
   fprintf(fidOut, '-------\n');

   for id = 1:length(sensorInfoData.sensorName)
      fprintf(fidOut, '%s\n', sensorInfoData.sensorName{id});
      fprintf(fidOut, 'sensor_type_vocabulary; %s\n', sensorInfoData.sensorTypeVoc{id});
      fprintf(fidOut, 'long_name; %s\n', sensorInfoData.sensorLongName{id});
      fprintf(fidOut, 'sensor_model; %s\n', sensorInfoData.sensorSensorModel{id});
      fprintf(fidOut, 'sensor_model_vocabulary; %s\n', sensorInfoData.sensorSensorModelVoc{id});
      fprintf(fidOut, 'sensor_maker; %s\n', sensorInfoData.sensorSensorMaker{id});
      fprintf(fidOut, 'sensor_maker_vocabulary; %s\n', sensorInfoData.sensorSensorMakerVoc{id});
      fprintf(fidOut, 'sensor_serial_number; %s\n', sensorInfoData.sensorSensorSerialNo{id});
      fprintf(fidOut, 'sensor_calibration_date; %s\n', sensorInfoData.sensorSensorCalbDate{id});
      fprintf(fidOut, '-------\n');
   end

   fprintf(fidOut, '*********\n');
   fprintf(fidOut, 'MEAS DATA\n');
   fprintf(fidOut, '*********\n');

   dataStr = repmat({''}, dimensions{2}, length(paramData)/2);
   colNum = 1;
   for idM = 1:2:length(paramData)
      paramName = paramData{idM};
      paramMeas = paramData{idM+1};
      switch (paramName)
         case {'TIME', 'TIME_GPS'}
            idNoDef = find(paramMeas ~= -1);
            dataStr(:, colNum) = repmat({'-1'}, length(paramMeas), 1);
            % dataStr(idNoDef, colNum) = cellstr(gl_julian_2_gregorian(gl_epoch_2_julian(paramMeas(idNoDef))));
            dataStr(idNoDef, colNum) = cellstr([repmat(' ', length(idNoDef), 1) gl_julian_2_gregorian(gl_epoch_2_julian(paramMeas(idNoDef)))]);
            colNum = colNum + 1;
         case {'LATITUDE', 'LONGITUDE', 'LATITUDE_GPS', 'LONGITUDE_GPS'}
            valStr = textscan(sprintf('%.3f@', paramMeas), '%s', 'delimiter', '@');
            dataStr(:, colNum) = valStr{:};
            colNum = colNum + 1;
         otherwise
            if ~((length(paramName) > 2) && strcmp(paramName(end-2:end), '_QC'))
               valStr = textscan(sprintf('%g@', paramMeas), '%s', 'delimiter', '@');
               dataStr(:, colNum) = valStr{:};
               colNum = colNum + 1;
            else
               valStr = textscan(sprintf('%d@', paramMeas), '%s', 'delimiter', '@');
               dataStr(:, colNum) = valStr{:};
               colNum = colNum + 1;
            end
      end
   end

   paramNameList = paramData(1:2:end);
   valStr = sprintf('%s;', paramNameList{:});
   fprintf(fidOut, '#;');
   fprintf(fidOut, '%s\n', valStr(1:end-1));
   fprintf(fidOut, '-------\n');
   for idL = 1:size(dataStr, 1)
      valCell = dataStr(idL, :);
      valStr = sprintf('%s;', valCell{:});
      fprintf(fidOut, '%d;', idL);
      fprintf(fidOut, '%s\n', valStr(1:end-1));
   end

   fclose(fidOut);
end

return
