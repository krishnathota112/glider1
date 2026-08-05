% ------------------------------------------------------------------------------
% Generate OceanGliders NetCDF file from EGO NetCDF file.
%
% The default behaviour is :
%    - to generate all the deployments (the directories) stored in the
%      DIR_INPUT_NC_FILES directory
% this behaviour can be modified by input arguments.
%
% SYNTAX :
%   nc_ego_2_ocean_gliders(varargin)
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
%   02/04/2025 - RNU - creation
% ------------------------------------------------------------------------------
function nc_ego_2_ocean_gliders(varargin)

% top directory of input files
DIR_INPUT_NC_FILES = 'C:\Users\jprannou\_DATA\GLIDER\FORMAT_1.5\';

% top directory of output files
DIR_OUTPUT_NC_FILES = 'C:\Users\jprannou\_DATA\GLIDER\FORMAT_1.5\';

% directory to store the log file
DIR_LOG_FILE = 'C:\Users\jprannou\_RNU\Glider\work\log\';

% default values initialization
gl_init_default_values;

% real time processing
global g_decGl_realtimeFlag;
g_decGl_realtimeFlag = 0;

% create and start log file recording
logFile = [DIR_LOG_FILE '/' 'nc_ego_2_ocean_gliders_' datestr(now, 'yyyymmddTHHMMSS') '.log'];
diary(logFile);
tic;

% check input arguments
inputDirName = [];
outputDirName = [];
deployName = [];
if (nargin > 0)
   if (rem(nargin, 2) ~= 0)
      fprintf('ERROR: expecting an even number of input arguments (e.g. (''argument_name'', ''argument_value'') => exit\n');
      diary off;
      return
   else
      for id = 1:2:nargin
         if (strcmpi(varargin{id}, 'data'))
            if (exist([DIR_INPUT_NC_FILES '/' varargin{id+1}], 'dir'))
               inputDirName = [DIR_INPUT_NC_FILES '/' varargin{id+1}];
               outputDirName = [DIR_OUTPUT_NC_FILES '/' varargin{id+1}];
               deployName = varargin{id+1};
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

% convert EGO file
if ~(exist(DIR_OUTPUT_NC_FILES, 'dir') == 7)
   mkdir(DIR_OUTPUT_NC_FILES);
end
if (isempty(inputDirName))
   % convert all the EGO files of the DIR_INPUT_NC_FILES directory
   dirInfo = dir(DIR_INPUT_NC_FILES);
   for dirNum = 1:length(dirInfo)
      if ~(strcmp(dirInfo(dirNum).name, '.') || strcmp(dirInfo(dirNum).name, '..'))
         inputDirName = [DIR_INPUT_NC_FILES '/' dirInfo(dirNum).name];
         deployName = dirInfo(dirNum).name;
         outputDirName = [DIR_OUTPUT_NC_FILES '/' dirInfo(dirNum).name];
         if ~(exist(outputDirName, 'dir') == 7)
            mkdir(outputDirName);
         end
         nc_ego_2_ocean_gliders_file(deployName, inputDirName, outputDirName);
      end
   end
else
   if ~(exist(outputDirName, 'dir') == 7)
      mkdir(outputDirName);
   end
   
   % convert the EGO file of this deployment
   nc_ego_2_ocean_gliders_file(deployName, inputDirName, outputDirName);
end

ellapsedTime = toc;
fprintf('done (Elapsed time is %.1f seconds)\n', ellapsedTime);

diary off;

return
