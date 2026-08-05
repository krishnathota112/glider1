% ------------------------------------------------------------------------------
% Update "EGO_format_version" value in JSON deployment and sensor files from EGO
% 1.4 to EGO 1.5.
% The default behaviour is :
%    - to process all the deployments (the directories) stored in the
%      DATA_DIRECTORY directory
% this behaviour can be modified by input arguments.
%
% SYNTAX :
%   gl_update_json_files_from_1_4_to_1_5(varargin)
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
%   11/14/2024 - RNU - creation
% ------------------------------------------------------------------------------
function gl_update_json_files_from_1_4_to_1_5(varargin)

% top directory of the deployment directories
DATA_DIRECTORY = 'C:\Users\jprannou\_DATA\GLIDER\FORMAT_1.5/';

% directory to store log files
DIR_LOG_FILE = 'C:\Users\jprannou\_RNU\Glider\work\log\';

% default values initialization
gl_init_default_values;


% create and start log file recording
logFile = [DIR_LOG_FILE '/' 'gl_update_json_files_from_1_4_to_1_5_' datestr(now, 'yyyymmddTHHMMSS') '.log'];
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
         update_json_files( ...
            [DATA_DIRECTORY '/' dirName '/'], ...
            dirName);
      end
   end
else
   % process the data of this deployment
   update_json_files( ...
      dataToProcessDir, ...
      deploymentDirName);
end

ellapsedTime = toc;
fprintf('done (Elapsed time is %.1f seconds)\n', ellapsedTime);

diary off;

return

% ------------------------------------------------------------------------------
% Update "EGO_format_version" value in JSON deployment and sensor files from EGO
% 1.4 to EGO 1.5.
%
% SYNTAX :
%  update_json_files(a_deploymentDirName, a_deploymentName)
%
% INPUT PARAMETERS :
%   a_deploymentDirName : name of the deployment directory
%   a_deploymentName    : name of the deployment
%
% OUTPUT PARAMETERS :
%
% EXAMPLES :
%
% SEE ALSO :
% AUTHOR : Jean-Philippe Rannou (Capgemini) (jean.philippe.rannou@partenaire-exterieur.ifremer.fr)
% ------------------------------------------------------------------------------
% RELEASES :
%   11/14/2024 - RNU - creation
% ------------------------------------------------------------------------------
function update_json_files(a_deploymentDirName, a_deploymentName)

% check that json deployment file is in version 1.4
deployJsonInputFile = [a_deploymentDirName '/json/' a_deploymentName '.json'];
if ~(exist(deployJsonInputFile, 'file') == 2)
   fprintf('ERROR: expected json deployment file not found (%s) => deployment ignored\n', ...
      deployJsonInputFile);
   return
end

% read the json deployment file
try
   deployJsonData = gl_load_json(deployJsonInputFile);
catch MException
   fprintf('ERROR: error format in json file (%s)\n', ...
      deployJsonInputFile);
   fprintf('%s\n', ...
      MException.message);
   return
end

okGo = 0;
if (isfield(deployJsonData, 'EGO_format_version'))
   if (strcmp(deployJsonData.EGO_format_version, '1.4'))
      okGo = 1;
   end
end
if (~okGo)
   fprintf('ERROR: json file not in expected 1.4 version (%s)\n', ...
      deployJsonInputFile);
   return
end

% rename input directory
inputDirName = [a_deploymentDirName '/json_1.4_' datestr(now, 'yyyymmddTHHMMSS') '/'];
outputDirName = [a_deploymentDirName '/json/'];

movefile(outputDirName, inputDirName)

% create output directory
mkdir(outputDirName);

% update deployment file
fprintf('Updating json deployment file: %s\n', [a_deploymentName '.json']);

ok = update_file([inputDirName a_deploymentName '.json'], ...
   [outputDirName a_deploymentName '.json']);
if (~ok)
   return
end

% update sensor files
glSensorList = deployJsonData.glider_sensor;
for idGs = 1:length(glSensorList)
   glSensor = glSensorList(idGs);
   sensorFileName = glSensor.sensor_file_name;

   sensorJsonInputFile = [inputDirName sensorFileName];
   sensorJsonOutputFile = [outputDirName sensorFileName];

   fprintf('Updating json deployment file: %s\n', ...
      sensorFileName);

   update_file(sensorJsonInputFile, sensorJsonOutputFile);
   if (~ok)
      return
   end
end

return

% ------------------------------------------------------------------------------
% Update "EGO_format_version" value in JSON file from 1.4 to EGO 1.5.
%
% SYNTAX :
% [o_ok] = update_file(a_jsonInputFile, a_jsonOutputFile)
%
% INPUT PARAMETERS :
%   a_jsonInputFile  : input json file to be updated
%   a_jsonOutputFile : output updated json file
%
% OUTPUT PARAMETERS :
%   o_ok : 1: file successfully updated, 0 otherwise
%
% EXAMPLES :
%
% SEE ALSO :
% AUTHOR : Jean-Philippe Rannou (Capgemini) (jean.philippe.rannou@partenaire-exterieur.ifremer.fr)
% ------------------------------------------------------------------------------
% RELEASES :
%   11/14/2024 - RNU - creation
% ------------------------------------------------------------------------------
function [o_ok] = update_file(a_jsonInputFile, a_jsonOutputFile)

% output parameters initialization
o_ok = 0;

% read input file
fId = fopen(a_jsonInputFile, 'r');
if (fId == -1)
   fprintf('ERROR: error while opening file (%s)\n', ...
      a_jsonInputFile);
   return
end

lines = [];
while 1
   line = fgetl(fId);
   if (line == -1)
      break
   end
   lines{end+1} = line;
end

fclose(fId);

% replace "EGO_format_version" value
idF = find(contains(lines, '"EGO_format_version"'));
if (length(idF) ~= 1)
   if (isempty(idF))
      fprintf('ERROR: cannot find ''"EGO_format_version"'' in file (%s)\n', ...
         deployJsonInputFile);
      return
   else
      fprintf('ERROR: %d occurences of ''"EGO_format_version"'' in file (%s)\n', ...
         length(idF), deployJsonInputFile);
      return
   end
end
lines{idF} = regexprep(lines{idF}, '1.4', '1.5');

% write output file
fId = fopen(a_jsonOutputFile, 'w');
if (fId == -1)
   fprintf('ERROR: error while creating file (%s)\n', ...
      a_jsonOutputFile);
end

fprintf(fId, '%s\n', lines{:});

fclose(fId);

o_ok = 1;

return
