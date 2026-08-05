% ------------------------------------------------------------------------------
% Slocum glider have two different inputs (m_de_oil_vol (for deep slocum) and
% m_ballast_pumped (for shallow slocum)) for TECH_ballast_pumped data. We should
% update the labels when glider data have been read.
%
% SYNTAX :
% [o_jsonDeployData] = gl_update_slocum_tech_labels(a_jsonDeployData)
%
% INPUT PARAMETERS :
%   a_jsonDeployData : input data of json deployment file
%
% OUTPUT PARAMETERS :
%   o_jsonDeployData : input data of json deployment file
%
% EXAMPLES :
%
% SEE ALSO :
% AUTHOR : Jean-Philippe Rannou (Capgemini) (jean.philippe.rannou@partenaire-exterieur.ifremer.fr)
% ------------------------------------------------------------------------------
% RELEASES :
%   10/23/2023 - RNU - creation
% ------------------------------------------------------------------------------
function [o_jsonDeployData] = gl_update_slocum_tech_labels(a_jsonDeployData)

% output parameter initialization
o_jsonDeployData = a_jsonDeployData;

% shallow or deep slocum glider
global g_decGl_shallowSlocumGlider;

% variable names defined in the json deployment file
global g_decGl_gliderVarName;
global g_decGl_gliderAdjVarName;
global g_decGl_gliderVarPathName;
global g_decGl_egoVarName;

% calibration information defined in the json deployment file
global g_decGl_calibInfo;

% DOXY processing Id defined in the json deployment file
global g_decGl_processingId;


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% update the global variables

if (any(strcmp('TECH_ballast_pumped1', g_decGl_egoVarName)))
   if (g_decGl_shallowSlocumGlider ~= -1)
      if (g_decGl_shallowSlocumGlider == 1)
         idF1 = find(strcmp('TECH_ballast_pumped1', g_decGl_egoVarName));
         idF2 = find(strcmp('TECH_ballast_pumped1_C', g_decGl_egoVarName));
         g_decGl_egoVarName{idF1} = 'TECH_ballast_pumped';
         g_decGl_egoVarName{idF2} = 'TECH_ballast_pumped_C';
         idF1 = find(strcmp('TECH_ballast_pumped2', g_decGl_egoVarName));
         g_decGl_gliderVarName(idF1) = [];
         g_decGl_gliderAdjVarName(idF1) = [];
         g_decGl_gliderVarPathName(idF1) = [];
         g_decGl_egoVarName(idF1) = [];
         g_decGl_calibInfo(idF1) = [];
         g_decGl_processingId(idF1) = [];
         idF1 = find(strcmp('TECH_ballast_pumped2_C', g_decGl_egoVarName));
         g_decGl_gliderVarName(idF1) = [];
         g_decGl_gliderAdjVarName(idF1) = [];
         g_decGl_gliderVarPathName(idF1) = [];
         g_decGl_egoVarName(idF1) = [];
         g_decGl_calibInfo(idF1) = [];
         g_decGl_processingId(idF1) = [];
      else
         idF1 = find(strcmp('TECH_ballast_pumped2', g_decGl_egoVarName));
         idF2 = find(strcmp('TECH_ballast_pumped2_C', g_decGl_egoVarName));
         g_decGl_egoVarName{idF1} = 'TECH_ballast_pumped';
         g_decGl_egoVarName{idF2} = 'TECH_ballast_pumped_C';
         idF1 = find(strcmp('TECH_ballast_pumped1', g_decGl_egoVarName));
         g_decGl_gliderVarName(idF1) = [];
         g_decGl_gliderAdjVarName(idF1) = [];
         g_decGl_gliderVarPathName(idF1) = [];
         g_decGl_egoVarName(idF1) = [];
         g_decGl_calibInfo(idF1) = [];
         g_decGl_processingId(idF1) = [];
         idF1 = find(strcmp('TECH_ballast_pumped1_C', g_decGl_egoVarName));
         g_decGl_gliderVarName(idF1) = [];
         g_decGl_gliderAdjVarName(idF1) = [];
         g_decGl_gliderVarPathName(idF1) = [];
         g_decGl_egoVarName(idF1) = [];
         g_decGl_calibInfo(idF1) = [];
         g_decGl_processingId(idF1) = [];
      end
   else
      idF1 = find(strcmp('TECH_ballast_pumped1', g_decGl_egoVarName));
      idF2 = find(strcmp('TECH_ballast_pumped1_C', g_decGl_egoVarName));
      g_decGl_egoVarName{idF1} = 'TECH_ballast_pumped';
      g_decGl_egoVarName{idF2} = 'TECH_ballast_pumped_C';
      idF1 = find(strcmp('TECH_ballast_pumped2', g_decGl_egoVarName));
      g_decGl_gliderVarName(idF1) = [];
      g_decGl_gliderAdjVarName(idF1) = [];
      g_decGl_gliderVarPathName(idF1) = [];
      g_decGl_egoVarName(idF1) = [];
      g_decGl_calibInfo(idF1) = [];
      g_decGl_processingId(idF1) = [];
      idF1 = find(strcmp('TECH_ballast_pumped2_C', g_decGl_egoVarName));
      g_decGl_gliderVarName(idF1) = [];
      g_decGl_gliderAdjVarName(idF1) = [];
      g_decGl_gliderVarPathName(idF1) = [];
      g_decGl_egoVarName(idF1) = [];
      g_decGl_calibInfo(idF1) = [];
      g_decGl_processingId(idF1) = [];
   end
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% update data of json deployment file

idDel = [];
for idP = 1:length(o_jsonDeployData.parametersList)
   if (strcmp(o_jsonDeployData.parametersList{idP}.ego_variable_name, 'TECH_ballast_pumped1'))
      if (g_decGl_shallowSlocumGlider ~= 0)
         o_jsonDeployData.parametersList{idP}.ego_variable_name = 'TECH_ballast_pumped';
      else
         idDel = [idDel idP];
      end
   elseif (strcmp(o_jsonDeployData.parametersList{idP}.ego_variable_name, 'TECH_ballast_pumped1_C'))
      if (g_decGl_shallowSlocumGlider ~= 0)
         o_jsonDeployData.parametersList{idP}.ego_variable_name = 'TECH_ballast_pumped_C';
      else
         idDel = [idDel idP];
      end
   elseif (strcmp(o_jsonDeployData.parametersList{idP}.ego_variable_name, 'TECH_ballast_pumped2'))
      if (g_decGl_shallowSlocumGlider == 0)
         o_jsonDeployData.parametersList{idP}.ego_variable_name = 'TECH_ballast_pumped';
      else
         idDel = [idDel idP];
      end
   elseif (strcmp(o_jsonDeployData.parametersList{idP}.ego_variable_name, 'TECH_ballast_pumped2_C'))
      if (g_decGl_shallowSlocumGlider == 0)
         o_jsonDeployData.parametersList{idP}.ego_variable_name = 'TECH_ballast_pumped_C';
      else
         idDel = [idDel idP];
      end
   end
end
o_jsonDeployData.parametersList(idDel) = [];

idDel = [];
idF = find(strcmp(o_jsonDeployData.glider_parameter_data.PARAMETER, 'TECH_ballast_pumped1'));
if (g_decGl_shallowSlocumGlider ~= 0)
   o_jsonDeployData.glider_parameter_data.PARAMETER{idF} = 'TECH_ballast_pumped';
else
   idDel = [idDel idF];
end
idF = find(strcmp(o_jsonDeployData.glider_parameter_data.PARAMETER, 'TECH_ballast_pumped1_C'));
if (g_decGl_shallowSlocumGlider ~= 0)
   o_jsonDeployData.glider_parameter_data.PARAMETER{idF} = 'TECH_ballast_pumped_C';
else
   idDel = [idDel idF];
end
idF = find(strcmp(o_jsonDeployData.glider_parameter_data.PARAMETER, 'TECH_ballast_pumped2'));
if (g_decGl_shallowSlocumGlider == 0)
   o_jsonDeployData.glider_parameter_data.PARAMETER{idF} = 'TECH_ballast_pumped';
else
   idDel = [idDel idF];
end
idF = find(strcmp(o_jsonDeployData.glider_parameter_data.PARAMETER, 'TECH_ballast_pumped2_C'));
if (g_decGl_shallowSlocumGlider == 0)
   o_jsonDeployData.glider_parameter_data.PARAMETER{idF} = 'TECH_ballast_pumped_C';
else
   idDel = [idDel idF];
end
o_jsonDeployData.glider_parameter_data.PARAMETER(idDel) = [];
o_jsonDeployData.glider_parameter_data.PARAMETER_SENSOR(idDel) = [];
o_jsonDeployData.glider_parameter_data.PARAMETER_DATA_MODE(idDel) = [];
o_jsonDeployData.glider_parameter_data.PARAMETER_UNITS(idDel) = [];
o_jsonDeployData.glider_parameter_data.PARAMETER_ACCURACY(idDel) = [];
o_jsonDeployData.glider_parameter_data.PARAMETER_RESOLUTION(idDel) = [];

idDel = [];
idF = find(strcmp(o_jsonDeployData.glider_parameter_derivation_data.DERIVATION_PARAMETER, 'TECH_ballast_pumped1'));
if (g_decGl_shallowSlocumGlider ~= 0)
   o_jsonDeployData.glider_parameter_derivation_data.DERIVATION_PARAMETER{idF} = 'TECH_ballast_pumped';
else
   idDel = [idDel idF];
end
idF = find(strcmp(o_jsonDeployData.glider_parameter_derivation_data.DERIVATION_PARAMETER, 'TECH_ballast_pumped1_C'));
if (g_decGl_shallowSlocumGlider ~= 0)
   o_jsonDeployData.glider_parameter_derivation_data.DERIVATION_PARAMETER{idF} = 'TECH_ballast_pumped_C';
else
   idDel = [idDel idF];
end
idF = find(strcmp(o_jsonDeployData.glider_parameter_derivation_data.DERIVATION_PARAMETER, 'TECH_ballast_pumped2'));
if (g_decGl_shallowSlocumGlider == 0)
   o_jsonDeployData.glider_parameter_derivation_data.DERIVATION_PARAMETER{idF} = 'TECH_ballast_pumped';
else
   idDel = [idDel idF];
end
idF = find(strcmp(o_jsonDeployData.glider_parameter_derivation_data.DERIVATION_PARAMETER, 'TECH_ballast_pumped2_C'));
if (g_decGl_shallowSlocumGlider == 0)
   o_jsonDeployData.glider_parameter_derivation_data.DERIVATION_PARAMETER{idF} = 'TECH_ballast_pumped_C';
else
   idDel = [idDel idF];
end
o_jsonDeployData.glider_parameter_derivation_data.DERIVATION_PARAMETER(idDel) = [];
o_jsonDeployData.glider_parameter_derivation_data.DERIVATION_EQUATION(idDel) = [];
o_jsonDeployData.glider_parameter_derivation_data.DERIVATION_COEFFICIENT(idDel) = [];
o_jsonDeployData.glider_parameter_derivation_data.DERIVATION_COMMENT(idDel) = [];
o_jsonDeployData.glider_parameter_derivation_data.DERIVATION_DATE(idDel) = [];

return
