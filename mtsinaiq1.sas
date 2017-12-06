****************************
Program: mtsinaiq1.sas
Author:  Ram Varma
Notes:
Our sales team was just approached by a large employer, interested in a COE for gastroenterology 
procedures. The client's health plan gave us an episode dataset to assess the opportunity within 
colonoscopy procedures.  Key questions we have include the following:
q1) What is Mount Sinai’s cost relative to the market?
q2) What drives variability in episode cost?
q3) Are there Mount Sinai providers that should be included in the program to create an 
affordable offering? 

Data: SampleEmployerData.zip
****************************;

**data import: 
  Notes: using proc import with our unix directories thus ommited;
	
**macros:;
	%let by_var1= setting;
	%let by_var2= gastrophysician_category;

	%macro _delsasds(sasdata);
	  %if %sysfunc(exist(&sasdata)) %then %do;
	    %if %index(&sasdata, .) %then %do;
	      proc datasets library=%scan(&sasdata, 1, .) nolist;
	        delete %scan(&sasdata, 2, .);
	      run;
	      quit;
	    %end;
	    %else %do;
	      proc datasets library=work nolist;
	        delete &sasdata;
	      run;
	      quit;
	    %end;
	  %end;
	%mend _delsasds;

**Adding quarter, yearmo, and provider and facility combo to better understand the role:;
data SAMPLEEMPLOYERDATA;
	set SAMPLEEMPLOYERDATA;
	quarter =put (service_dt, yyq4.);
	yearmo = put (service_dt, yymmn6.);
	prov_fac_combo = catx ("_", gastrophysician_scrambled, facility_scrambled);
run;

proc contents data=SAMPLEEMPLOYERDATA 
			   out=emp_contents;
run;

proc sql;
	create table dol_amts as 
		select distinct scan(name , 1, '_') as type, name
		from emp_contents
		where upper(name) like "%AMT%"
			and scan(name , 1, '_') not in ('lab','pathology','other');
quit;

/********************************************************/
/*q1) What is Mount Sinai’s cost relative to the market?*/
/********************************************************/

**General Descriptives to understand various costs associated with an episode:;

%macro fac_means(ct=);
proc sort data=SAMPLEEMPLOYERDATA;
	by facility_scrambled setting;

proc means data=SAMPLEEMPLOYERDATA noprint;
	var episode_allwd_amt;
	by facility_scrambled setting;
	output out=_means(drop=_type_ _freq_) mean= median= std= n=/ autoname;
	where   colonoscopy_type = "&ct";
run;

proc sql;
create table &ct._fac_means as 
select DISTINCT a.*, b.gastrophysician_category
from _means a
join SAMPLEEMPLOYERDATA b
 on a.facility_scrambled = b.facility_scrambled
order by setting, a.facility_scrambled;
quit;
%mend;
%fac_means(ct=diagnostic);
%fac_means(ct=therapeutic);

%macro ct_type (CT);
		%macro gen_smry (type, cost);
		proc sort data=SAMPLEEMPLOYERDATA;
			by  &by_var1 &by_var2;

		proc means data=SAMPLEEMPLOYERDATA noprint;
			var &cost;
			by  &by_var1 &by_var2;
			output out=&type._means(drop=_type_ _freq_) mean= median= std= n=/ autoname;
			where colonoscopy_type = "&CT";
		run;

		data &type._means;
			set &type._means;
			type = "&type";
			colonoscopy_type  = "&CT";
		run;

				ods graphics on;

				%macro box_plot (setting);
					title Box Plot &type &CT and setting  %qsysfunc(compress(&&setting,%str(%")));

					proc boxplot data=SAMPLEEMPLOYERDATA;
						plot &cost*&by_var2/
							boxstyle = schematic
							horizontal;
						where colonoscopy_type =  "&CT" and setting =  &setting;
					run;
				%mend;

		%box_plot ("Amb. Surg. Center");
		%box_plot ("Hosp. Outpatient");
		%box_plot ("Office");		
		ods graphics off; 
		%mend;

data _NULL_;
	set dol_amts ;
 	call execute('%gen_smry('||type||','||name||')');
run;
%mend;

**Colonoscopy Types should be run seperately:;
%ct_type (CT=diagnostic);
%ct_type (CT=therapeutic);


/********************************************************/
/*q2) What drives variability in episode cost?			*/
/********************************************************/

**Capping:
Notes: Capping is determined by looking at the plot of the percentiles. 
	   Another Method of capping is looking at the # of SD away from the mean;
%macro cap (ct );
%let type = %qsysfunc(compress(&ct,%str(%")));

	proc univariate data=SAMPLEEMPLOYERDATA noprint;
		var episode_allwd_amt;
		class  setting;
		output out= x1 pctlpre=P_ pctlpts= 90  to 100 by 0.2;
		where colonoscopy_type = &ct;
	run;

	proc sort data= x1;
		by setting;
 
	proc transpose data=x1 out= &type (drop=_label_);
		by setting;
		var p_90--p_100;
	run;

	proc sort data=&type;
		by  setting;
	run;

	ods graphics on;

	axis1 label= (  h=1 justify = c 'Percentiles');
	axis2 label= ( 	h=1 'Episode Allowed Amount');
	title Plot of percentiles - &CT;
	PROC GPLOT DATA = &type;
		BY SETTING;
		PLOT COL1 * _NAME_/ haxis= axis1  vaxis=axis2;
	run;

	ods graphics off;
%mend;
%cap (ct = "diagnostic" );
%cap (ct = "therapeutic" );

data q2_analyisis;
	set SAMPLEEMPLOYERDATA;
	format capped_episode_amt dollar12.;

	/*Cap1 | setting=Amb. Surg. Center | 98.6*/
	if (setting= "Amb. Surg. Center" and colonoscopy_type = "diagnostic"  and  episode_allwd_amt > 3735.88) then
		cap_episode_allwd_amt =  3735.88;

	/*Cap2 | setting=Hosp. Outpatient | 95.5 */
	if (setting= "Hosp. Outpatient" and colonoscopy_type = "diagnostic"  and  episode_allwd_amt > 8514.61) then
		cap_episode_allwd_amt =  8514.61;

	/*Cap3 | setting=Office | 98.2 */
	if (setting= "Office" and colonoscopy_type = "diagnostic"  and  episode_allwd_amt > 1834.33) then
		cap_episode_allwd_amt =  1834.33;

	/*Cap1 | setting=Amb. Surg. Center | 98.2*/
	if (setting= "Amb. Surg. Center" and colonoscopy_type = "therapeutic"  and  episode_allwd_amt > 5051.69) then
		cap_episode_allwd_amt =  5051.69;

	/*Cap2 | setting=Hosp. Outpatient | 96.5 */
	if (setting= "Hosp. Outpatient" and colonoscopy_type = "therapeutic"  and  episode_allwd_amt >9389.47) then
		cap_episode_allwd_amt =  9389.47;

	/*Cap3 | setting=Office | 99.6 */
	if (setting= "Office" and colonoscopy_type = "therapeutic"  and  episode_allwd_amt > 3624.58) then
	cap_episode_allwd_amt =  3624.58;
	
	/*LOWER CAPS:*/
	if (setting= "Amb. Surg. Center" and colonoscopy_type = "therapeutic"  and  episode_allwd_amt<=317.02) then
		cap_episode_allwd_amt =317.02; 
	if (setting= "Amb. Surg. Center" and colonoscopy_type = "diagnostic"  and  episode_allwd_amt<=809.21) then
		cap_episode_allwd_amt =809.21; 

	capped_episode_amt = coalesce (cap_episode_allwd_amt, episode_allwd_amt);
	drop cap_episode_allwd_amt  episode_allwd_amt;
run;
 

**Diagnostic:;
**Remove q316 because there were only 3 observations during that period;
proc freq data=q2_analyisis;
	tables  quarter*gastrophysician_category yearmo setting*gastrophysician_category/list missing;
	where colonoscopy_type = "diagnostic";
run;

ods trace on;
proc glm data = q2_analyisis;
  class quarter  (ref="15Q1" ) 
		gastrophysician_category  (ref = 'NonMSHS')
		setting;
  model capped_episode_amt =
		quarter   
		gastrophysician_category 
		setting 
/ p ss3 solution;
OUTPUT OUT=stats P=pred R=res L95=lower U95=upper; 
where colonoscopy_type = "diagnostic"  and quarter ne '16Q3';
run;
ods trace off;

**Therapeutic:;
**Office was missing in the diagnostic thus the check here:;
proc freq data=q2_analyisis;
	tables quarter*gastrophysician_category yearmo setting*gastrophysician_category/list missing;
	where colonoscopy_type = "therapeutic";
run;

ods trace on;
proc glm data = q2_analyisis;
  class quarter   (ref="15Q1" ) 
		gastrophysician_category (ref = 'NonMSHS')
		setting;
  model capped_episode_amt =
		quarter   
		gastrophysician_category 
		setting 	     	 
/  p ss3 solution;
OUTPUT OUT=stats P=pred R=res L95=lower U95=upper; 
where colonoscopy_type = "therapeutic" and quarter ne '16Q3';
run;
ods trace off;
 

/*
q3) Are there Mount Sinai providers that should be included in the program to create an 
affordable offering? 
*/

**Assuming I had more data points, I am going to use cluster analysis:;
%macro cluster_type (  ct, type);
		%macro  cluster (setting);
		proc sql;
			create table std_comp as
				select mean (capped_episode_amt )  	as episode_allwd_amt ,
					   mean (gastro_allwd_amt) 		as gastro_allwd_amt,
					   gastrophysician_scrambled, 
					   gastrophysician_category
					from  q2_analyisis
						where colonoscopy_type = &ct and setting= &setting
							group by 
									gastrophysician_scrambled, 
					   				gastrophysician_category;
		quit;

		proc fastclus data =  std_comp maxclusters =3 radius=0
					  out=  %qsysfunc(compress(&&setting,%str(%". ))) ; 
		  var  episode_allwd_amt							
				gastro_allwd_amt;
		  id  gastrophysician_scrambled;
		run;

		data %qsysfunc(compress(&&setting,%str(%". )));
		set %qsysfunc(compress(&&setting,%str(%". )));
			setting = &setting;
		run;

		%mend; 
		%cluster ("Office");
		%cluster ("Amb. Surg. Center");
		%cluster ("Hosp. Outpatient");

		data &type._all_clust_types; 
		set AMBSURGCENTER 	 
			HOSPOUTPATIENT 	 
			OFFICE 			 ;	
 		COLONONSCOPY_TYPE=&ct; 	 
		run;
%mend;
%cluster_type  ( ct = "diagnostic" , type=diag);
%cluster_type  ( ct = "therapeutic" , type=thera);

proc sort data=DIAG_ALL_CLUST_TYPES;
	by gastrophysician_category cluster setting;

proc means data=DIAG_ALL_CLUST_TYPES;
	by gastrophysician_category;
	class cluster setting;
	var episode_allwd_amt;
run;

proc sort data=thera_ALL_CLUST_TYPES;
	by gastrophysician_category cluster setting;

proc means data=thera_ALL_CLUST_TYPES;
	by gastrophysician_category;
	class cluster setting;
	var episode_allwd_amt;
run;

%macro clust_plots (ct, set);
title Plot of Distance*Episode Amt (Cap) - &CT | &set;
proc sgplot data=&ct._ALL_CLUST_TYPES;
	scatter y=distance x=episode_allwd_amt 
		/ 	group=cluster	
			groupdisplay=cluster  
			clusterwidth=0.9		 
			markerattrs=(size=11 );
	where setting = &set;
run;
%mend;

**Diag:;
%clust_plots (ct=diag, set="Office");
%clust_plots (ct=diag, set="Amb. Surg. Center");
%clust_plots (ct=diag, set="Hosp. Outpatient");

**Thera:;
%clust_plots (ct=thera, set="Office");
%clust_plots (ct=thera, set="Amb. Surg. Center");
%clust_plots (ct=thera, set="Hosp. Outpatient");
 
