% ------------------------------------------------------------------------------
% Add a reference json file in deployment to manage TECH parameters.
% The default behaviour is :
%    - to process all the deployments (the directories) stored in the
%      DATA_DIRECTORY directory
% this behaviour can be modified by input arguments.
%
% SYNTAX :
%   gl_add_json_tech_file(varargin)
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
%   07/31/2023 - RNU - creation
% ------------------------------------------------------------------------------
function gl_add_json_tech_file(varargin)

% top directory of the deployment directories
DATA_DIRECTORY = 'C:\Users\jprannou\_DATA\GLIDER\FORMAT_1.4/';
DATA_DIRECTORY = 'E:\GLIDER\slocum/';
DATA_DIRECTORY = 'E:\GLIDER\seaexplorer/';
DATA_DIRECTORY = 'F:\GLIDER\seaglider/';

% directory to store log files
DIR_LOG_FILE = 'C:\Users\jprannou\_RNU\Glider\work\log\';

% reference file for JSON deployment file
JSON_TECH_REF_FILE = 'C:\Users\jprannou\_RNU\Glider\soft\util\json\slocum_sensor_TECH_1.4.json';
JSON_TECH_REF_FILE = 'C:\Users\jprannou\_RNU\Glider\soft\util\json\seaexplorer_sensor_TECH_1.4.json';
JSON_TECH_REF_FILE = 'C:\Users\jprannou\_RNU\Glider\soft\util\json\seaglider_sensor_TECH_1.4.json';

% default values initialization
gl_init_default_values;


% create and start log file recording
logFile = [DIR_LOG_FILE '/' 'gl_add_json_tech_file_' datestr(now, 'yyyymmddTHHMMSS') '.log'];
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
         gl_add_json_tech_file_( ...
            [DATA_DIRECTORY '/' dirName '/'], ...
            dirName, ...
            JSON_TECH_REF_FILE);
      end
   end
else
   % process the data of this deployment
   gl_add_json_tech_file_( ...
      dataToProcessDir, ...
      deploymentDirName, ...
      JSON_TECH_REF_FILE);
end

ellapsedTime = toc;
fprintf('done (Elapsed time is %.1f seconds)\n', ellapsedTime);

diary off;

return

% ------------------------------------------------------------------------------
% Add a reference json file in deployment to manage TECH parameters.
%
% SYNTAX :
% gl_add_json_tech_file_(a_deploymentDirName, a_deploymentName, a_jsonTechRefFile)
%
% INPUT PARAMETERS :
%   a_deploymentDirName    : name of the deployment directory
%   a_deploymentName       : name of the deployment
%   gl_add_json_tech_file_ : json TECH reference file
%
% OUTPUT PARAMETERS :
%
% EXAMPLES :
%
% SEE ALSO :
% AUTHOR : Jean-Philippe Rannou (Capgemini) (jean.philippe.rannou@partenaire-exterieur.ifremer.fr)
% ------------------------------------------------------------------------------
% RELEASES :
%   07/31/2023 - RNU - creation
% ------------------------------------------------------------------------------
function gl_add_json_tech_file_(a_deploymentDirName, a_deploymentName, a_jsonTechRefFile)

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% check that the main json file is in version 1.4
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
   if (strcmp(deployJsonData.EGO_format_version, '1.4'))
      okGo = 1;
   end
end
if (~okGo)
   fprintf('ERROR: json file not in expected 1.4 version (%s)\n', ...
      deployJsonFile);
   return
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% make a copy of the existing json directory
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

deployJsonDir = [a_deploymentDirName '/json/'];
deployJsonDirOld = [a_deploymentDirName '/json_without_json_tech_file/'];
copyfile(deployJsonDir, deployJsonDirOld);

fprintf('Processing json deployment file: %s\n', ...
   deployJsonFile);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% read json deployment file and add json TECH file to "glider_sensor" structure
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% read JSON deployment file
fIdIn = fopen(deployJsonFile, 'r');
if (fIdIn == -1)
   fprintf('ERROR: While openning file : %s\n', deployJsonFile);
   return
end

% read the data
deployJsonData = [];
while (1)
   line = fgetl(fIdIn);
   if (line == -1)
      break
   end
   deployJsonData{end+1} = line;
end
fclose(fIdIn);

% update file contents
idF = cellfun(@(x) strfind(deployJsonData, x), {'"sensor_file_name":'}, 'UniformOutput', 0);
idF = find(~cellfun(@isempty, idF{:}));
if (~isempty(idF))

   [~, jsonTechRefFileName, ext] = fileparts(a_jsonTechRefFile);

   dataCell = [ ...
      {'        },'} ...
      {'        {'} ...
      {sprintf('            "sensor_file_name": "%s"', [jsonTechRefFileName ext])}];

   deployJsonData = [deployJsonData(1:idF(end)) dataCell deployJsonData(idF(end)+1:end)];

   % copy json TECH reference file in the json directory
   deployJsonDir = [a_deploymentDirName '/json/'];
   copyfile(a_jsonTechRefFile, deployJsonDir);

end

% write updated file file
fIdOut = fopen(deployJsonFile, 'wt');
if (fIdOut == -1)
   fprintf('ERROR: While creating file : %s\n', deployJsonFile);
   return
end

fprintf(fIdOut, '%s\n', deployJsonData{:});

fclose(fIdOut);

return
