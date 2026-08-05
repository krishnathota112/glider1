% ------------------------------------------------------------------------------
% Check if a dimension is part of a variable dimension list.
%
% SYNTAX :
 % [o_present] = gl_dim_is_present_in_var(a_ncId, a_varName, a_dimName)
%
% INPUT PARAMETERS :
%   a_ncId    : NetCDF file Id
%   a_varName : variable name
%   a_dimName : dimension name
%
% OUTPUT PARAMETERS :
%   o_present : 1 if the dimension is one of the variable ones
%
% EXAMPLES :
%
% SEE ALSO : 
% AUTHOR : Jean-Philippe Rannou (Capgemini) (jean.philippe.rannou@partenaire-exterieur.ifremer.fr)
% ------------------------------------------------------------------------------
% RELEASES :
%   08/30/2023 - RNU - creation
% ------------------------------------------------------------------------------
function [o_present] = gl_dim_is_present_in_var(a_ncId, a_varName, a_dimName)

o_present = 0;

if (gl_var_is_present(a_ncId, a_varName))
   varId = netcdf.inqVarID(a_ncId, a_varName);
   [varName, xType, dimIds, nbAtts] = netcdf.inqVar(a_ncId, varId);

   for idDim = dimIds
      [dimName, dimLen] = netcdf.inqDim(a_ncId, idDim);
      if (strcmp(dimName, a_dimName))
         o_present = 1;
         break
      end
   end
end

return
