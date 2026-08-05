% ------------------------------------------------------------------------------
% Add 'MTIME' parameter in profiles.
%
% SYNTAX :
%  [o_tabProfiles] = gl_add_mtime_in_profile(a_tabProfiles)
%
% INPUT PARAMETERS :
%   a_tabProfiles : input profile structures
%
% OUTPUT PARAMETERS :
%   o_tabProfiles : output profile structures
%
% EXAMPLES :
%
% SEE ALSO : 
% AUTHOR : Jean-Philippe Rannou (Capgemini) (jean.philippe.rannou@partenaire-exterieur.ifremer.fr)
% ------------------------------------------------------------------------------
% RELEASES :
%   08/29/2022 - RNU - created for Coriolis Argo decoder
%   01/16/2023 - RNU - updated for Coriolis EGO decoder
% ------------------------------------------------------------------------------
function [o_tabProfiles] = gl_add_mtime_in_profile(a_tabProfiles)

% output parameters initialization
o_tabProfiles = a_tabProfiles;

% global default values
global g_decGl_ncDateDef;
global g_decGl_qcStrNoQc;


% add MTIME parameter into profiles
paramMtime = gl_get_netcdf_param_attributes('MTIME');
paramJuld = gl_get_netcdf_param_attributes('JULD');
for idProf = 1:length(o_tabProfiles)
   
   profStruct = o_tabProfiles(idProf);

   if ((profStruct.date ~= g_decGl_ncDateDef) && ...
         (~isempty(profStruct.dates)) && ...
         (any(profStruct.dates ~= paramJuld.fillValue)))

      mtimeData = ones(size(profStruct.data, 1), 1)*paramMtime.fillValue;
      idDated = find(profStruct.dates ~= paramJuld.fillValue);
      mtimeData(idDated) = profStruct.dates(idDated) - profStruct.date;

      profStruct.paramList = [paramMtime profStruct.paramList];
      profStruct.data = cat(2, mtimeData, double(profStruct.data));
      if (~isempty(profStruct.dataQc))
         profStruct.dataQc = cat(2, repmat(g_decGl_qcStrNoQc, size(profStruct.dataQc, 1), 1), profStruct.dataQc);
      end

      if (~isempty(profStruct.dataAdj))
         profStruct.dataAdj = cat(2, ones(size(profStruct.dataAdj, 1), 1)*paramMtime.fillValue, double(profStruct.dataAdj));
      end
      if (~isempty(profStruct.dataAdjQc))
         profStruct.dataAdjQc = cat(2, repmat(g_decGl_qcStrNoQc, size(profStruct.dataAdjQc, 1), 1), profStruct.dataAdjQc);
      end

      if (~isempty(profStruct.paramNumberWithSubLevels))
         profStruct.paramNumberWithSubLevels = profStruct.paramNumberWithSubLevels + 1;
      end
      
      if (~isempty(profStruct.paramDataMode))
         profStruct.paramDataMode = ['R' profStruct.paramDataMode];
      end

      o_tabProfiles(idProf) = profStruct;
   end
end

return
