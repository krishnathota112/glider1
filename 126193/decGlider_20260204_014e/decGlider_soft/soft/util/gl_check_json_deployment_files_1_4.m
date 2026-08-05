% ------------------------------------------------------------------------------
% Check that json files of a deployment are compliant with EGO 1.4 format.
% The default behaviour is :
%    - to process all the deployments (the directories) stored in the
%      DATA_DIRECTORY directory
% this behaviour can be modified by input arguments.
%
% SYNTAX :
%   gl_check_json_deployment_files_1_4(varargin)
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
%   02/19/2019 - RNU - creation
% ------------------------------------------------------------------------------
function gl_check_json_deployment_files_1_4(varargin)

% top directory of the deployment directories
% DATA_DIRECTORY = 'C:\Users\jprannou\_DATA\GLIDER\FORMAT_1.4';
DATA_DIRECTORY = 'C:\Users\jprannou\_DATA\GLIDER\slocum/';
% DATA_DIRECTORY = 'C:\Users\jprannou\_DATA\GLIDER\seaglider/';
% DATA_DIRECTORY = 'C:\Users\jprannou\_DATA\GLIDER\seaexplorer/';
DATA_DIRECTORY = 'C:\Users\jprannou\_DATA\GLIDER\out/';

% directory to store the log file
DIR_LOG_FILE = 'C:\Users\jprannou\_RNU\Glider\work\log\';

% default values initialization
gl_init_default_values;

% flag for specific input (NetCDF file of sea glider)
global g_decGl_seaGliderInputNc;
g_decGl_seaGliderInputNc = 0;


% create and start log file recording
logFile = [DIR_LOG_FILE '/' 'gl_check_json_deployment_files_1_4_' datestr(now, 'yyyymmddTHHMMSS') '.log'];
diary(logFile);
tic;

% check input arguments
dataToProcessDir = [];
deploymentName = [];
if (nargin > 0)
   if (rem(nargin, 2) ~= 0)
      fprintf('ERROR: expecting an even number of input arguments (e.g. (''argument_name'', ''argument_value'') => exit\n');
      diary off;
      return
   else
      for id = 1:2:nargin
         if (strcmpi(varargin{id}, 'data'))
            if (exist([DATA_DIRECTORY '/' varargin{id+1}], 'dir'))
               deploymentName = varargin{id+1};
               dataToProcessDir = [DATA_DIRECTORY '/' deploymentName];
            else
               fprintf('WARNING: %s is not an existing directory => ignored\n', varargin{id+1});
            end
         else
            fprintf('WARNING: unexpected input argument (%s) => ignored\n', varargin{id});
         end
      end
   end
end

% check json files
if (isempty(dataToProcessDir))
   % check json files for all the deployments of the DATA_DIRECTORY directory
   dirInfo = dir(DATA_DIRECTORY);
   for dirNum = 1:length(dirInfo)
      dirName = dirInfo(dirNum).name;
      dirPathName = [DATA_DIRECTORY '/' dirName];
      if ~(strcmp(dirInfo(dirNum).name, '.') || strcmp(dirInfo(dirNum).name, '..'))
         if (isfolder(dirPathName))
            jsonDeploymentFilePathName = [DATA_DIRECTORY '/' dirName '/json/' dirName '.json'];
            gl_check_json_deployment_file_1_4(jsonDeploymentFilePathName);
         end
      end
   end
else
   % check json files of this deployment
   jsonDeploymentFilePathName = [dataToProcessDir '/json/' deploymentName '.json'];
   gl_check_json_deployment_file_1_4(jsonDeploymentFilePathName);
end

ellapsedTime = toc;
fprintf('done (Elapsed time is %.1f seconds)\n', ellapsedTime);

diary off;

return
