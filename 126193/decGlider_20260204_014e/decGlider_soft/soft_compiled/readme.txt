================================
README
================================
Step to operate the compiled application:

1) Prerequisites for Deployment 
Verify that version 9.13 (R2022b) of the MATLAB Runtime is installed. 
If not:
	- Download and install the Linux version of the MATLAB Runtime for R2022b (9.13 64 bits) from the following link on the MathWorks website: https://www.mathworks.com/products/compiler/matlab-runtime.html
	- (installation command on linux : ./install at the root of the MATLAB Runtime archive)

2) Define configuration file 
Refer to the decoder user manual to know what the variables correspond to.

Notes :
- GEBCO_2024.nc (for TEST004_GEBCO_FILE variable) can be downloaded here https://www.bodc.ac.uk/data/open_download/gebco/gebco_2024/zip/
- gl_greylist.txt (for TEST015_GREY_LIST_FILE variable) file available in the decGlider_misc folder of this archive.
- EGO_format_1.5.json file (for EGO_FORMAT_JSON_FILE variable) is available in the decGlider_soft/soft/json/ folder of this archive.
- XML_DIRECTORY variable is not used in this compiled version.



3) Run gl_process_glider application

Available files:
- gl_process_glider 
- run_gl_process_glider.sh (shell script for temporarily setting environment variables and 
                           executing the application)
- _glider_decoder_conf.txt (configuration file)				   
- This readme file 


To run the shell script, type
./run_gl_process_glider.sh <mcr_directory> <argument_list>

at Linux or Mac command prompt. <mcr_directory> is the directory 
where MATLAB Runtime is installed or the directory where 
MATLAB is installed on the machine. <argument_list> is all the 
arguments you want to pass to your application. For example, 

Exemple:
./run_gl_process_glider.sh /usr/local/MATLAB/MATLAB_Runtime/R2022b/ glidertype seaexplorer data kraken_eurec_tmp
