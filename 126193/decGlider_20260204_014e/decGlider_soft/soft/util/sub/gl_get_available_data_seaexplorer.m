% ------------------------------------------------------------------------------
% Retrieve the variable names of a Seaexplorer and information on data (useful data).
%
% SYNTAX :
%  [o_availableParam, o_availableData] = gl_get_available_data_seaexplorer(a_deploymentTopDirName, a_deploymentDirName)
%
% INPUT PARAMETERS :
%   a_deploymentTopDirName : top directory of deployments directory
%   a_deploymentDirName    : directory of the deployment
%
% OUTPUT PARAMETERS :
%   o_availableParam : list of parameter names for the deployment
%   o_availableData  : 1 if useful data exist, 0 otherwise
%
% EXAMPLES :
%
% SEE ALSO :
% AUTHOR : Jean-Philippe Rannou (Capgemini) (jean.philippe.rannou@partenaire-exterieur.ifremer.fr)
% ------------------------------------------------------------------------------
% RELEASES :
%   10/31/2023 - RNU - creation
% ------------------------------------------------------------------------------
function [o_availableParam, o_availableData] = gl_get_available_data_seaexplorer(a_deploymentTopDirName, a_deploymentDirName)

% output parameters initialization
o_availableParam = [];
o_availableData = [];

% directory of glider data
gliderDataDirName = [a_deploymentTopDirName '/' a_deploymentDirName '/gz/'];
if (exist(gliderDataDirName, 'dir') == 7)
   gzFile = 1;
else
   gliderDataDirName = [a_deploymentTopDirName '/' a_deploymentDirName '/csv/'];
   if (exist(gliderDataDirName, 'dir') == 7)
      gzFile = 0;
   else
      fprintf('ERROR: data directory not found in : %s\n', [a_deploymentTopDirName '/' a_deploymentDirName]);
      return
   end
end

% read data
if (gzFile == 1)
   fileList = dir([gliderDataDirName '*.gli.*.gz']);
   fileList = [fileList; dir([gliderDataDirName '*.pl*.*.gz'])];
else
   fileList = dir([gliderDataDirName '*.pld*.raw.*']);
   fileList = [fileList; dir([gliderDataDirName '*.gli.*'])];
   fileList = [fileList; dir([gliderDataDirName '*.pl*.*'])];
end
for idFile = 1:length(fileList)

   inputFileName = fileList(idFile).name;
   inputPathFileName = [gliderDataDirName '/' inputFileName];

   if (gzFile == 1)
      % unziped the 2 files in the 'tmp' directory
      [pathZipFileName, fileName, ext] = fileparts(inputPathFileName) ;
      filePathName = regexprep(pathZipFileName, '/gz', '/tmp');
      try
         gunzip(inputPathFileName, filePathName);
      catch MException
         switch MException.identifier
            case {'MATLAB:io:archive:extractArchive:internalError', ...
                  'MATLAB:io:archive:gunzip:javaCopyStreamError'}
               fprintf('WARNING: File corrupted (%s) : %s\n', MException.message, inputPathFileName);
               continue
         end
         rethrow(MException)
      end
      movefile([filePathName '/' fileName], [filePathName '/' fileName '.csv']);
      inputFileName = [fileName '.csv'];
      inputPathFileName = [filePathName '/' inputFileName];
   end

   % open the input file and read the data description
   fIdIn = fopen(inputPathFileName, 'r');
   if (fIdIn == -1)
      fprintf('ERROR: While openning file : %s\n', inputPathFileName);
      continue
   end

   % read the data
   header = [];
   while 1
      line = fgetl(fIdIn);
      if (line == -1)
         break
      end
      if (~isempty(line))
         header = line;
         break
      end
   end

   fclose(fIdIn);

   % parse the data
   header = textscan(header, '%s', 'delimiter', ';');
   varNameList = unique(header{:}, 'stable');
   loadData = 0;
   for idV = 1:length(varNameList)
      varName = strtrim(varNameList{idV});
      if (~any(strcmp(varName, o_availableParam)))
         loadData = 1;
         break
      else
         idF = find(strcmp(varName, o_availableParam));
         if (o_availableData(idF) == 0)
            loadData = 1;
            break
         end
      end
   end

   if (loadData)
      dataStruct = gl_read_seaexplorer_csv(inputPathFileName);

      for idV = 1:length(varNameList)
         varName = strtrim(varNameList{idV});
         if (~any(strcmp(varName, o_availableParam)))
            data = dataStruct.(varName);
            o_availableParam{end+1} = varName;
            o_availableData(end+1) = any(~isnan(data) & (data ~= -9999) & (data ~= 9999));
         else
            idF = find(strcmp(varName, o_availableParam));
            if (o_availableData(idF) == 0)
            data = dataStruct.(varName);
               o_availableData(idF) = any(~isnan(data) & (data ~= -9999) & (data ~= 9999));
            end
         end
      end
   end
end

tmpDirPathName = [a_deploymentTopDirName '/' a_deploymentDirName '/tmp/'];
if (exist(tmpDirPathName, 'dir'))
   rmdir(tmpDirPathName, 's')
end

[~, idSort] = sort(o_availableParam);
o_availableParam = o_availableParam(idSort);
o_availableData = o_availableData(idSort);

return
