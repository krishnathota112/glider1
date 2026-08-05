% ------------------------------------------------------------------------------
% Retrieve the variable names of a Slocum and information on data (useful data).
%
% SYNTAX :
% [o_availableParam, o_availableParamDim, o_availableData, ...
%   o_availableCoef, o_availableCoefV, o_dataType] = ...
%   gl_get_available_data_seaglider(a_deploymentTopDirName, a_deploymentDirName)
%
% INPUT PARAMETERS :
%   a_deploymentTopDirName : top directory of deployments directory
%   a_deploymentDirName    : directory of the deployment
%
% OUTPUT PARAMETERS :
%   o_availableParam    : list of parameter names for the deployment
%   o_availableParamDim : list of parameter dimension names for the deployment
%   o_availableData     : 1 if useful data exist, 0 otherwise
%   o_availableCoef     : list of coef (var with no dimension)
%   o_availableCoefV    : coef values
%   o_dataType          : type of input data
%
% EXAMPLES :
%
% SEE ALSO :
% AUTHOR : Jean-Philippe Rannou (Capgemini) (jean.philippe.rannou@partenaire-exterieur.ifremer.fr)
% ------------------------------------------------------------------------------
% RELEASES :
%   12/19/2017 - RNU - creation
% ------------------------------------------------------------------------------
function [o_availableParam, o_availableParamDim, o_availableData, ...
   o_availableCoef, o_availableCoefV, o_dataType] = ...
   gl_get_available_data_seaglider(a_deploymentTopDirName, a_deploymentDirName)

% output parameters initialization
o_availableParam = [];
o_availableParamDim = [];
o_availableData = [];
o_availableCoef = [];
o_availableCoefV = [];
o_dataType = '';

% directory of glider data
gliderDataDirName = [a_deploymentTopDirName '/' a_deploymentDirName '/nc_sg/'];
if (exist(gliderDataDirName, 'dir') == 7)
   o_dataType = 'nc';
else
   gliderDataDirName = [a_deploymentTopDirName '/' a_deploymentDirName '/bpo/'];
   if (exist(gliderDataDirName, 'dir') == 7)
      o_dataType = 'bpo';
   else
      gliderDataDirName = [a_deploymentTopDirName '/' a_deploymentDirName '/pro/'];
      if (exist(gliderDataDirName, 'dir') == 7)
         o_dataType = 'pro';
      else
         gliderDataDirName = [a_deploymentTopDirName '/' a_deploymentDirName '/eng/'];
         if (exist(gliderDataDirName, 'dir') == 7)
            o_dataType = 'eng';
         end
      end
   end
end

switch (o_dataType)
   case 'nc'

      % read data
      nFiles = dir([gliderDataDirName '/' '*.nc']);
      for idFile = 1:length(nFiles)

         nFileName = nFiles(idFile).name;
         nPathFileName = [gliderDataDirName '/' nFileName];

         % open NetCDF file
         fCdf = netcdf.open(nPathFileName, 'NC_NOWRITE');
         if (isempty(fCdf))
            fprintf('ERROR: Unable to open NetCDF input file: %s\n', nPathFileName);
            return
         end

         % get useful dimensions
         dimList = [];
         [nbDims, nbVars, nbGAtts, unlimId] = netcdf.inq(fCdf);
         for idDim = 0:nbDims-1
            [dimName, dimLen] = netcdf.inqDim(fCdf, idDim);
            if (~strncmp(dimName, 'string_', length('string_')))
               dimList{end+1} = dimName;
            end
         end

         % get variables associated to useful dimensions
         for idDim = 1:length(dimList)
            varList =  gl_var_list_using_dim(fCdf, dimList{idDim});
            for idV = 1:length(varList)
               idVar = netcdf.inqVarID(fCdf, varList{idV});
               [varName, varType, varDims, nbAtts] = netcdf.inqVar(fCdf, idVar);
               dimList2 = [];
               for idDim2 = varDims
                  [dimname, dimlen] = netcdf.inqDim(fCdf, idDim2);
                  dimList2{end+1} = dimname;
               end
               dimListStr = sprintf('%s,', dimList2{:});
               if (~any(strcmp(varName, o_availableParam)))
                  o_availableParam{end+1} = varName;
                  o_availableParamDim{end+1} = dimListStr(1:end-1);
                  paramData = netcdf.getVar(fCdf, netcdf.inqVarID(fCdf, varName));
                  if (gl_att_is_present(fCdf, varName, '_FillValue'))
                     fillVal = netcdf.getAtt(fCdf, netcdf.inqVarID(fCdf, varName), '_FillValue');
                     o_availableData(end+1) = any(~isnan(paramData) & (paramData ~= fillVal));
                  else
                     o_availableData(end+1) = any(~isnan(paramData));
                  end
               else
                  idF = find(strcmp(varName, o_availableParam));
                  if (o_availableData(idF) == 0)
                     paramData = netcdf.getVar(fCdf, netcdf.inqVarID(fCdf, varName));
                     if (gl_att_is_present(fCdf, varName, '_FillValue'))
                        fillVal = netcdf.getAtt(fCdf, netcdf.inqVarID(fCdf, varName), '_FillValue');
                        o_availableData(idF) = any(~isnan(paramData) & (paramData ~= fillVal));
                     else
                        o_availableData(idF) = any(~isnan(paramData));
                     end
                  end
               end
            end
         end

         for idV = 0:nbVars-1
            [varName, varType, varDims, nbAtts] = netcdf.inqVar(fCdf, idV);
            % if (isempty(varDims) && ismember(varName, useful_coef_name_list))
            if (isempty(varDims) && any(strfind(varName, 'sg_cal_')))
               if (~any(strcmp(varName, o_availableCoef)))
                  o_availableCoef{end+1} = varName;
                  o_availableCoefV{end+1} = netcdf.getVar(fCdf, idV);
               end
            end
         end

         netcdf.close(fCdf);
      end

   case {'bpo', 'pro', 'eng'}

      % read data
      if (strcmp(o_dataType, 'bpo'))
         files = dir([gliderDataDirName '/' '*.bpo']);
         dataSep = ',';
      elseif (strcmp(o_dataType, 'pro'))
         files = dir([gliderDataDirName '/' '*.pro']);
         dataSep = ',';
      elseif (strcmp(o_dataType, 'eng'))
         files = dir([gliderDataDirName '/' '*.eng']);
         dataSep = ' ';
      end

      for idFile = 1:length(files)

         fileName = files(idFile).name;
         pathFileName = [gliderDataDirName '/' fileName];

         % open the input file and read the data description
         fId = fopen(pathFileName, 'r');
         if (fId == -1)
            fprintf('ERROR: Unable to open file: %s\n', pathFileName);
            return
         end

         lineVar = '';
         while (1)
            line = fgetl(fId);
            if (line == -1)
               break
            end
            if (any(strfind(line, '%columns:')))
               lineVar = line;
               break
            end
         end

         fclose(fId);

         if (isempty(lineVar))
            fprintf('ERROR: No var list in file: %s\n', bPathFileName);
            return
         end

         idF = strfind(lineVar, '%columns:');
         lineVar = lineVar(idF+length('%columns:'):end);
         varNameList = split(lineVar, ',');
         varNameList = regexprep(varNameList, '\.', '_');
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

            % open the input file and read the data description
            fId = fopen(pathFileName, 'r');
            if (fId == -1)
               fprintf('ERROR: Unable to open file: %s\n', pathFileName);
               return
            end

            dataStart = 0;
            dataAll = [];
            while (1)
               line = fgetl(fId);
               if (line == -1)
                  break
               end

               if (dataStart)
                  dataStr = split(line, dataSep);
                  if (isempty(dataStr{end}))
                     dataStr(end) = [];
                  end
                  if (length(dataStr) == length(varNameList))
                     dataNum = str2double(dataStr)';
                     dataAll = [dataAll; dataNum];
                  else
                     % fprintf('ERROR\n');
                  end
               end

               if (any(strfind(line, '%data:')))
                  dataStart = 1;
               end
            end

            fclose(fId);

            for idV = 1:length(varNameList)
               varName = strtrim(varNameList{idV});
               if (~any(strcmp(varName, o_availableParam)))
                  o_availableParam{end+1} = varName;
                  o_availableData(end+1) = any(~isnan(dataAll(:, idV)));
               else
                  idF = find(strcmp(varName, o_availableParam));
                  if (o_availableData(idF) == 0)
                     o_availableData(idF) = any(~isnan(dataAll(:, idV)));
                  end
               end
            end
         end
      end
      o_availableParamDim = repmat({'na'}, size(o_availableParam));
   otherwise
      fprintf('ERROR: data directory not found\n');
end

return

function o_coefNameList = useful_coef_name_list

o_coefNameList = [ ...
    {'sg_cal_WETLabsCalData_wlbbfl2_Scatter700_scaleFactor'    }
    {'sg_cal_WETLabsCalData_wlbbfl2_Scatter700_darkCounts'     }
    {'sg_cal_WETLabsCalData_wlbbfl2_Chlorophyll_scaleFactor'   }
    {'sg_cal_WETLabsCalData_wlbbfl2_Chlorophyll_darkCounts'    }
    {'sg_cal_WETLabsCalData_wlbbfl2_CDOM_scaleFactor'          }
    {'sg_cal_WETLabsCalData_wlbbfl2_CDOM_darkCounts'           }
];

return

