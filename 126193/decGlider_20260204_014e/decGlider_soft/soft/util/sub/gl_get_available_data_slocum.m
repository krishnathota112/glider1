% ------------------------------------------------------------------------------
% Retrieve the variable names of a Slocum and information on data (useful data).
%
% SYNTAX :
%  [o_availableParam, o_availableData] = gl_get_available_data_slocum(a_deploymentTopDirName, a_deploymentDirName)
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
%   12/19/2017 - RNU - creation
% ------------------------------------------------------------------------------
function [o_availableParam, o_availableData] = gl_get_available_data_slocum(a_deploymentTopDirName, a_deploymentDirName)

% output parameters initialization
o_availableParam = [];
o_availableData = [];

% directory of glider data
gliderDataDirName = [a_deploymentTopDirName '/' a_deploymentDirName '/dat/'];
if ~(exist(gliderDataDirName, 'dir') == 7)
   fprintf('ERROR: directory not found: %s\n', gliderDataDirName);
   return
end

% read data
mFiles = dir([gliderDataDirName '/*.m']);
for idFile = 1:length(mFiles)
   
   mFileName = mFiles(idFile).name;
   mPathFileName = [gliderDataDirName '/' mFileName];
   
   % retrieve segment data parameters
   currentSegmentParamName = gl_slocum_get_param_name(mPathFileName);
   
   loadDataFlag = 0;
   for idP = 1:length(currentSegmentParamName)
      gliderParam = lower(currentSegmentParamName{idP});
      if (~any(strcmp(gliderParam, o_availableParam)))
         loadDataFlag = 1;
         break
      else
         idF = find(strcmp(gliderParam, o_availableParam));
         if (o_availableData(idF) == 0)
            loadDataFlag = 1;
            break
         end
      end
   end
   
   if (loadDataFlag == 1)
      
      % read segment data
      currentSegmentData = gl_slocum_read_data(mPathFileName);
      
      data = currentSegmentData.data;
      currentSegmentData = rmfield(currentSegmentData, 'data');
      listFields = fieldnames(currentSegmentData);
      for idP = 1:length(listFields)
         varName = listFields{idP};
         if (size(data, 2) >= currentSegmentData.(varName))
            if (~any(strcmpi(varName, o_availableParam)))
               o_availableParam{end+1} = lower(varName);
               o_availableData(end+1) = any(~isnan(data(:, currentSegmentData.(varName))) & (data(:, currentSegmentData.(varName)) ~= 0));
            else
               idF = find(strcmpi(varName, o_availableParam));
               if (o_availableData(idF) == 0)
                  o_availableData(idF) = any(~isnan(data(:, currentSegmentData.(varName))) & (data(:, currentSegmentData.(varName)) ~= 0));
               end
            end
         end
      end
      clear data currentSegmentData
   end
end

[~, idSort] = sort(o_availableParam);
o_availableParam = o_availableParam(idSort);
o_availableData = o_availableData(idSort);

return

% ------------------------------------------------------------------------------
% Read Slocum available parameters.
%
% SYNTAX :
%  [o_paramNameList] = gl_slocum_get_param_name(a_mFileNameIn)
%
% INPUT PARAMETERS :
%   a_mFileNameIn    : name of the .m file from a yo
%
% OUTPUT PARAMETERS :
%   o_paramNameList : list of available parameters
%
% EXAMPLES :
%
% SEE ALSO :
% AUTHOR : Jean-Philippe Rannou (Capgemini) (jean.philippe.rannou@partenaire-exterieur.ifremer.fr)
% ------------------------------------------------------------------------------
% RELEASES :
%   02/20/2019 - RNU - creation
% ------------------------------------------------------------------------------
function [o_paramNameList] = gl_slocum_get_param_name(a_mFileNameIn)

% output parameter initialization
o_paramNameList = [];


% open the input file and read the data description
fId = fopen(a_mFileNameIn, 'r');
if (fId == -1)
   fprintf('ERROR: Unable to open file: %s\n', a_mFileNameIn);
   return
end

globalVarList = [];
while (1)
   line = fgetl(fId);
   
   if (line == -1)
      break
   end
   
   if (any(strfind(line, 'global')))
      globalVarList{end+1} = strtrim(regexprep(line, 'global', ''));
   elseif (any(strfind(line, '=')))
      idFEq = strfind(line, '=');
      varName = strtrim(line(1:idFEq(1)-1));
      if (any(strcmp(varName, globalVarList)))
         idFEnd = strfind(line, ';');
         varNum = strtrim(line(idFEq(1)+1:idFEnd(1)-1));
         if (~any(~ismember(varNum, 48:57)))
            o_paramNameList{end+1} = varName;
         end
      end
   end
end

fclose(fId);

return
