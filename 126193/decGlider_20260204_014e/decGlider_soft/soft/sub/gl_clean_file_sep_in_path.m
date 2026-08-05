% ------------------------------------------------------------------------------
% Clear separators in path name.
%
% SYNTAX :
% [o_dirPathName] = gl_clean_file_sep_in_path(a_dirPathName, a_dirFlag)
%
% INPUT PARAMETERS :
%   a_dirPathName : input path name
%   a_dirFlag     : 1 if it is a directory
%
% OUTPUT PARAMETERS :
%   o_dirPathName : output path name
%
% EXAMPLES :
%
% SEE ALSO :
% AUTHOR : Jean-Philippe Rannou (Capgemini) (jean.philippe.rannou@partenaire-exterieur.ifremer.fr)
% ------------------------------------------------------------------------------
% RELEASES :
%   11/06/2023 - RNU - creation
% ------------------------------------------------------------------------------
function [o_dirPathName] = gl_clean_file_sep_in_path(a_dirPathName, a_dirFlag)

% output data initialization
o_dirPathName = a_dirPathName;

if (filesep == '\')
   o_dirPathName = regexprep(o_dirPathName, '/', '\');
else
   o_dirPathName = regexprep(o_dirPathName, '\', '/');
end
o_dirPathName = regexprep(o_dirPathName, [filesep filesep], filesep);
if (a_dirFlag)
   if (o_dirPathName(end) ~= filesep)
      o_dirPathName = [o_dirPathName filesep];
   end
end

return
