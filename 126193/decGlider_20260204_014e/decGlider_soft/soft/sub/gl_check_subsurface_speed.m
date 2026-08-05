% ------------------------------------------------------------------------------
% Check subsurface position against surface ones (for horizontal velocity less
% than 3 m/s).
%
% SYNTAX :
%  [o_failedIds] = gl_check_subsurface_speed( ...
%    a_subSurfLocDate, a_subSurfLocLon, a_subSurfLocLat, ...
%    a_surfLocDate, a_surfLocLon, a_surfLocLat)
%
% INPUT PARAMETERS :
%   a_subSurfLocDate : subsurface location dates
%   a_subSurfLocLon  : subsurface location longitudes
%   a_subSurfLocLat  : subsurface location latitudes
%   a_surfLocDate    : surface location dates
%   a_surfLocLon     : surface location longitudes
%   a_surfLocLat     : surface location latitudes
%
% OUTPUT PARAMETERS :
%   o_failedIds : ids of subsurface locations that failed the test
%
% EXAMPLES :
%
% SEE ALSO :
% AUTHOR : Jean-Philippe Rannou (Capgemini) (jean.philippe.rannou@partenaire-exterieur.ifremer.fr)
% ------------------------------------------------------------------------------
% RELEASES :
%   03/06/2025 - RNU - creation
% ------------------------------------------------------------------------------
function [o_failedIds] = gl_check_subsurface_speed( ...
   a_subSurfLocDate, a_subSurfLocLon, a_subSurfLocLat, ...
   a_surfLocDate, a_surfLocLon, a_surfLocLat)

% output parameters initialization
o_failedIds = [];


if (isempty(a_surfLocDate))
   o_failedIds = 1:length(a_subSurfLocDate);
   return
end

% maximal surface velocity (m/s)
MAX_VEL = 3;

for idP = 1:length(a_subSurfLocDate)

   % look for the surface location to use to check the current subsurface one
   timeDiff = abs(a_surfLocDate - a_subSurfLocDate(idP))*1440;
   [~, idSort] = sort(timeDiff);
   idMin = find(timeDiff(idSort) > 10, 1); % 10 min difference to be sure to avoid similar times
   idMin = idSort(idMin);

   % compute the horizontal velocity between both locations
   distance = distance_lpo([a_subSurfLocLat(idP) a_surfLocLat(idMin)], [a_subSurfLocLon(idP) a_surfLocLon(idMin)]);
   speed = distance/(abs(a_subSurfLocDate(idP) - a_surfLocDate(idMin))*86400);

   if (speed > MAX_VEL)
      o_failedIds = [o_failedIds idP];
   end

end

return
