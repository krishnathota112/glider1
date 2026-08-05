% ------------------------------------------------------------------------------
% Set one (character) QC value to a set of existing ones.
%
% SYNTAX :
%  [o_qcValues] = gl_set_qc_str(a_qcValues, a_newQcValue)
%
% INPUT PARAMETERS :
%   a_qcValues   : existing set on QC values
%   a_newQcValue : QC value
%
% OUTPUT PARAMETERS :
%   o_qcValues : resulting set on QC values
%
% EXAMPLES :
%
% SEE ALSO :
% AUTHOR : Jean-Philippe Rannou (Capgemini) (jean.philippe.rannou@partenaire-exterieur.ifremer.fr)
% ------------------------------------------------------------------------------
% RELEASES :
%   04/11/2016 - RNU - creation
% ------------------------------------------------------------------------------
function [o_qcValues] = gl_set_qc_str(a_qcValues, a_newQcValue)

o_qcValues = a_qcValues;


if (~isempty(a_qcValues))
   o_qcValues = char(max(a_qcValues, double(repmat(a_newQcValue, size(a_qcValues)))));
end

return
