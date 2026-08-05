% ------------------------------------------------------------------------------
% Generate JSON deployment file from user JSON deployment and sensor files.
% BE CAREFULL : for Seaglider, the nc file data should be available.
%
% SYNTAX :
%   gl_create_json_deployment_files or
%   gl_create_json_deployment_files('data', 'crate_mooset00_38')
%
% INPUT PARAMETERS :
%   varargin : input arguments
%      must be provided in pairs i.e. ('argument_name', 'argument_value')
%      expected argument names:
%      'data' : identify the deployment (i.e. the sub-directory of the
%               DATA_DIRECTORY directory) to process
%      'glidertype' : specify the type of the glider to process (should be
%      one of the following types: 'seaglider', 'slocum', 'seaexplorer')
%
%      'glidertype' is mandatory; if 'data' argument is not provided, all the
%      deployments of the DATA_DIRECTORY directory are processed
%
% OUTPUT PARAMETERS :
%
% EXAMPLES :
%
% SEE ALSO :
% AUTHOR : Jean-Philippe Rannou (Capgemini) (jean.philippe.rannou@partenaire-exterieur.ifremer.fr)
% ------------------------------------------------------------------------------
% RELEASES :
%   12/19/2023 - RNU - creation
% ------------------------------------------------------------------------------
function gl_create_json_deployment_files(varargin)

% top directory of the input deployment directories
INPUT_DATA_DIRECTORY = 'C:\Users\jprannou\_DATA\GLIDER\output_json\slocum_json_final\';
INPUT_DATA_DIRECTORY = 'C:\Users\jprannou\_DATA\GLIDER\output_json\seaglider_json_final_with_data\';
% INPUT_DATA_DIRECTORY = 'C:\Users\jprannou\_DATA\GLIDER\output_json\seaexplorer_json_final\';

% directory to store the log file
DIR_LOG_FILE = 'C:\Users\jprannou\_RNU\Glider\work\log\';

% JSON REFERENCE FILE OF THE EGO 1.4 FORMAT
EGO_FORMAT_JSON_FILE = 'C:\Users\jprannou\_RNU\Glider\soft\json\EGO_format_1.4.json';

% reference json file of the EGO format
global g_decGl_egoFormatJsonFile;
g_decGl_egoFormatJsonFile = EGO_FORMAT_JSON_FILE;

% type of the glider to process
global g_decGl_gliderType;
g_decGl_gliderType = [];

% default values initialization
gl_init_default_values;


% check configuration information
if ~(exist(INPUT_DATA_DIRECTORY, 'dir') == 7)
   fprintf('ERROR: ''DATA_DIRECTORY'' directory not found: %s\n', DATA_DIRECTORY);
   return
end

if ~(exist(DIR_LOG_FILE, 'dir') == 7)
   fprintf('ERROR: ''DIR_LOG_FILE'' directory not found: %s\n', DIR_LOG_FILE);
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
         elseif (strcmpi(varargin{id}, 'glidertype'))
            if (strcmpi(varargin{id+1}, 'seaglider') || ...
                  strcmpi(varargin{id+1}, 'slocum') || ...
                  strcmpi(varargin{id+1}, 'seaexplorer'))
               g_decGl_gliderType = lower(varargin{id+1});
            else
               fprintf('ERROR: %s is not an expected glider type (expecting ''seaglider'' or ''slocum'' or ''seaexplorer'') => exit\n', varargin{id+1});
               return;
            end
         else
            fprintf('WARNING: unexpected input argument (%s) => ignored\n', varargin{id});
         end
      end
   end
end

if (isempty(g_decGl_gliderType))
   fprintf('ERROR: ''glidertype'' input argument is mandatory\n');
   return
end

% create and start log file recording
logFile = [DIR_LOG_FILE '/' 'gl_create_json_deployment_files_' deploymentDir '_' datestr(now, 'yyyymmddTHHMMSS') '.log'];
diary(logFile);
tic;

% generate deployment sensor files
if (isempty(deploymentDir))
   % check all the deployments of the DATA_DIRECTORY directory
   dirInfo = dir(INPUT_DATA_DIRECTORY);
   for dirNum = 1:length(dirInfo)
      if ~(strcmp(dirInfo(dirNum).name, '.') || strcmp(dirInfo(dirNum).name, '..'))
         dirName = dirInfo(dirNum).name;

         gl_create_json_deployment_files_(INPUT_DATA_DIRECTORY, dirName);
      end
   end
else
   % generate sensor files for this deployment
   gl_create_json_deployment_files_(INPUT_DATA_DIRECTORY, deploymentDir);
end

ellapsedTime = toc;
fprintf('done (Elapsed time is %.1f seconds)\n', ellapsedTime);

diary off;

return

% ------------------------------------------------------------------------------
% Generate JSON deployment file from user JSON deployment and sensor files.
%
% SYNTAX :
% gl_create_json_deployment_files_(a_deployInputDirName, a_deploymentDirName)
%
% INPUT PARAMETERS :
%   a_deployInputDirName  : top directory of input deployments directory
%   a_deployOutputDirName : top directory of output deployments directory
%   a_deploymentDirName   : directory of the deployment
%
% OUTPUT PARAMETERS :
%
% EXAMPLES :
%
% SEE ALSO :
% AUTHOR : Jean-Philippe Rannou (Capgemini) (jean.philippe.rannou@partenaire-exterieur.ifremer.fr)
% ------------------------------------------------------------------------------
% RELEASES :
%   12/19/2023 - RNU - creation
% ------------------------------------------------------------------------------
function gl_create_json_deployment_files_(a_deployInputDirName, a_deploymentDirName)

% reference json file of the EGO format
global g_decGl_egoFormatJsonFile;

% type of the glider to process
global g_decGl_gliderType;

% flag for specific input (NetCDF file of sea glider)
global g_decGl_seaGliderInputNc;


fprintf('Processing deployment: %s\n', a_deploymentDirName);

% check that the json file of the EGO format exists
if ~(exist(g_decGl_egoFormatJsonFile, 'file') == 2)
   fprintf('ERROR: expected json EGO file not found (%s) => deployment ignored\n', ...
      g_decGl_egoFormatJsonFile);
   return
end

% check that the 'json' directory exists
jsonDirName = [a_deployInputDirName filesep a_deploymentDirName filesep 'json' filesep];
if ~(exist(jsonDirName, 'dir') == 7)
   fprintf('ERROR: ''json'' directory not found for deployment (%s) => deployment ignored\n', ...
      a_deploymentDirName);
   return
end

% check that the JSON file of the deployment exist
jsonInputPathFile = [jsonDirName a_deploymentDirName '.json'];
if ~(exist(jsonInputPathFile, 'file') == 2)
   fprintf('ERROR: expected json deployment file not found (%s) => deployment ignored\n', ...
      jsonInputPathFile);
   return
end

% check input data type for seaglider
dataDirPathName = '';
depDirName = [a_deployInputDirName filesep a_deploymentDirName filesep];
if (strcmpi(g_decGl_gliderType, 'seaglider'))
   if (exist([depDirName 'bpo' filesep], 'dir') == 7)
      dataDirPathName = [depDirName 'bpo' filesep];
   elseif (exist([depDirName 'pro' filesep], 'dir') == 7)
      dataDirPathName = [depDirName 'pro' filesep];
   elseif (exist([depDirName 'eng' filesep], 'dir') == 7)
      dataDirPathName = [depDirName 'eng' filesep];
   elseif (exist([depDirName 'nc_sg' filesep], 'dir') == 7)
      g_decGl_seaGliderInputNc = 1;
      dataDirPathName = [depDirName 'nc_sg' filesep];
   else
      fprintf('ERROR: expecting a ''bpo'' or ''pro'' or ''eng'' or ''nc_sg'' sub-directory of %s => deployment ignored\n', ...
         a_deploymentDirName);
      return
   end
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% create the json file for the deployment (from 'json' directory contents)

% create the json file for the deployment (from 'json' directory contents)
deploymentFileName = gl_create_json_deployment_file( ...
   [a_deployInputDirName filesep a_deploymentDirName filesep], g_decGl_egoFormatJsonFile, dataDirPathName);
if (isempty(deploymentFileName))
   return
end

return
