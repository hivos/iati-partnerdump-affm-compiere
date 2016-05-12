-- IATI 2.02 Implementation for The Netherlands Ministry of Foreign Affairs

-- Copyright (C) 2016 Barry de Graaff <info@barrydegraaff.tk>, (C) 2012 Arthur Baan, (C) 2012 Fred Stoopendaal
-- This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
-- This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
-- You should have received a copy of the GNU General Public License along with this program. If not, see http://www.gnu.org/licenses/.

-- https://github.com/barrydegraaff/iati-partnerdump-affm-compiere

--Implement confidentiality filter before anything else
--Filter confidential contracts
CREATE OR REPLACE VIEW JASPER.HV_AFGO_COMMITMENT AS
SELECT * FROM AFGO_COMMITMENT 
WHERE CONFIDENTIALITYSTATUS = 'P' -- filter confidential records
AND AFGO_COMMITMENT.MASTERCOMMITMENT_ID IS NULL -- filter extension contracts
AND AFGO_COMMITMENT.DOCSTATUS IN ('CO','CL'); -- filter draft, invalid, void and so on

--Filter confidential business partners
CREATE OR REPLACE VIEW JASPER.HV_C_BPARTNER AS
SELECT * FROM C_BPARTNER WHERE CONFIDENTIALITYSTATUS = 'P';

--Here we skip some records that are a result of wrong input
CREATE OR REPLACE VIEW JASPER.HV_AFGO_FUNDSCHEDULE AS
SELECT * FROM AFGO_FUNDSCHEDULE 
WHERE AFGO_FUNDSCHEDULE_ID NOT IN (
'1011123',
'1011124',
'1011126',
'1011127',
'1011128',
'1011129',
'1011130',
'1011131',
'1011138',
'1011139',
'1011140',
'1011141',
'1011142',
'1011143',
'1011145',
'1011146'
);

CREATE OR REPLACE VIEW jasper.hv_iati202_buza_vw AS
SELECT
afgo_scheduleitem.afgo_projectcluster_id,
afgo_criteriumset.afgo_criteriumset_id,
afgo_criterium.afgo_criterium_id,
afgo_scheduleitem.afgo_scheduleitem_id,
afgo_scheduleitem.datedoc,
afgo_scheduleitemtype.name as afgo_scheduleitem_name,
afgo_criteriumset.description as setdescription,
afgo_criteriumset.help as sethelp,
afgo_criteriumset.documentnote as setnote,
afgo_criterium.description,
afgo_criterium.name as name,
afgo_criterium.help as help,
afgo_criterium.documentnote as documentnote,
case when to_char(ad_reference.description) = 'Float Number' then '1'
when to_char(ad_reference.description) ='10 Digit numeric' then '2' 
end as measure,
afgo_assessmentline.textscoreb,
afgo_assessmentline.integerscore,
afgo_assessmentline.numericscore,
afgo_assessmentline.longdescriptionb,
ad_ref_list.value
from afgo_scheduleitem
left outer join afgo_assessment on afgo_scheduleitem.afgo_scheduleitem_id = afgo_assessment.afgo_scheduleitem_id
left outer join afgo_assessmentline on afgo_assessmentline.afgo_assessment_id = afgo_assessment.afgo_assessment_id
left outer join afgo_criterium on afgo_assessmentline.afgo_criterium_id = afgo_criterium.afgo_criterium_id
left outer join ad_ref_list on afgo_assessmentline.listscore_id = ad_ref_list.ad_ref_list_id
left outer join afgo_scheduleitemtype on afgo_scheduleitem.afgo_scheduleitemtype_id = afgo_scheduleitemtype.afgo_scheduleitemtype_id
left outer join afgo_criteriumset on afgo_assessmentline.afgo_criteriumset_id = afgo_criteriumset.afgo_criteriumset_id
left outer join ad_reference on afgo_criterium.ad_reference_id = ad_reference.ad_reference_id;


CREATE OR REPLACE PACKAGE JASPER.hv_iati202_buza
is
   procedure mainprogram;
end;
/

CREATE OR REPLACE PACKAGE BODY JASPER.hv_iati202_buza
is
   procedure clobtofile (
      p_filename in varchar2
     ,p_dir      in varchar2
     ,p_clob     in clob
   )
   is
      c_amount constant binary_integer := 8000;
      l_buffer          varchar2 (32767);
      l_chr10           pls_integer;
      l_cloblen         pls_integer;
      l_fhandler        utl_file.file_type;
      l_pos             pls_integer := 1;
   begin
      l_cloblen  := dbms_lob.getlength (p_clob);
      l_fhandler := utl_file.fopen (p_dir, p_filename, 'W', c_amount * 2);
      while l_pos < l_cloblen
      loop
         l_buffer := dbms_lob.substr (p_clob, c_amount, l_pos);
         exit when l_buffer is null;
         l_chr10  := instr (l_buffer, chr (10), -1);
         if l_chr10 = 0
         then
		    if length (l_buffer) = c_amount
			then
               l_chr10  := instr (l_buffer, '><', -1);
               if l_chr10 = 0
               then
			      raise_application_error(-20101,'geen mogenlijkheid gevonden om de regel te splitsen');
			   else
                  l_buffer := substr (l_buffer, 1, l_chr10);
			   end if;
			end if;
            l_pos    := l_pos + length (l_buffer);
		 else
            l_buffer := substr (l_buffer, 1, l_chr10 - 1);
            l_pos    := l_pos + length (l_buffer) + 1;
         end if;
         utl_file.put_line (l_fhandler, l_buffer, true);
      end loop;
      utl_file.fclose (l_fhandler);
   exception
      when others
      then
         if utl_file.is_open (l_fhandler)
         then
            utl_file.fclose (l_fhandler);
         end if;
         raise;
   end clobtofile;
   
   procedure mainprogram
   is
      ll_xml clob;

      procedure pl (pl_text clob)
      is
      begin
         dbms_lob.append (ll_xml, dbms_xmlgen.convert (pl_text, dbms_xmlgen.entity_encode));
      exception
         when others then
            dbms_lob.writeappend (ll_xml, 9, '<![CDATA[');
            dbms_lob.append (ll_xml, pl_text);
            dbms_lob.writeappend (ll_xml, 4, ']]>' || chr (10));
      end;

      procedure p (lv_regel varchar2)
      is
      begin
         -- dbms_output.put_line (lv_regel);
         dbms_lob.writeappend (ll_xml, length (lv_regel) + 1, lv_regel || chr (10));
      end;

      function cd (lv_regel varchar2)
         return varchar2
      is
      begin
         return dbms_xmlgen.convert (lv_regel, dbms_xmlgen.entity_encode);
      exception
         when others then
            return '<![CDATA[' || lv_regel || ']]>';
      end;

      function cdata (lv_regel varchar2)
         return varchar2
      is
      begin
         return '<![CDATA[' || lv_regel || ']]>';
      end;
      
      begin
         dbms_lob.createtemporary (ll_xml, true, dbms_lob.session);
         
         p ('<?xml version="1.0" encoding="utf-8"?>');
         p ('<iati-activities version="2.02" generated-datetime="' || replace (to_char (sysdate, 'yyyy-mm-dd hh24:mi:ss'), ' ', 'T') || 'Z">');       
         
         --generate parent activities
         for activity in (
            select 
            afgo_fund.afgo_fund_id as afgo_fund_id,
            afgo_fund.updated as p_updated, 
            afgo_fund.referenceno as p_identifier,
            afgo_fund.description as p_title,
            afgo_fund.description as p_description,
            afgo_fund.startdate as p_datestart,
            afgo_fund.enddate as p_dateend
            from afgo_fund where afgo_fund_id in ('1010612','1010613','1010614')
            order by afgo_fund.documentno
         )
      
         loop
            p ('<iati-activity xml:lang="en" last-updated-datetime="' || replace (to_char (activity.p_updated, 'yyyy-mm-dd hh24:mi:ss'), ' ', 'T') || 'Z">');
            p ('<iati-identifier>NL-KVK-41198677-AFGO_FUND-'|| activity.p_identifier ||'</iati-identifier>');
            p ('<reporting-org ref="NL-KVK-41198677" type="21"><narrative><![CDATA[Hivos]]></narrative></reporting-org>');
            p ('<title><narrative><![CDATA['|| nvl(activity.p_title,'Untitled activity') ||']]></narrative></title>');
            p ('<description><narrative><![CDATA[' || nvl(activity.p_description,'Undescribed activity') || ']]></narrative></description>');
            p ('<participating-org ref="NL-KVK-41198677" role="2" type="21"></participating-org>');
            p ('<participating-org ref="XM-DAC-7" role="1" type="10"></participating-org>');
            p ('<activity-status code="2" />');
            p ('<activity-date iso-date="' || to_char (nvl(activity.p_datestart,sysdate), 'yyyy-mm-dd') || '" type="1" />');
            p ('<activity-date iso-date="' || to_char (nvl(activity.p_dateend,sysdate+1), 'yyyy-mm-dd') || '" type="3" />');
            p ('<contact-info type="1"><telephone>0031703765500</telephone><email>info@hivos.org</email></contact-info>');
            p ('<recipient-country code="NL" percentage="100" />');

            --budget loop
            for budget in (
               select 
               afgo_quarter.startdate as  p_startdate,
               afgo_quarter.enddate as  p_enddate,
               c_currency.iso_code as p_currency,
               sum(hv_afgo_fundschedule.grandtotal) as p_sum
               from jasper.hv_afgo_fundschedule
               inner join afgo_quarter on jasper.hv_afgo_fundschedule.afgo_quarter_id = afgo_quarter.afgo_quarter_id
               inner join c_currency on hv_afgo_fundschedule.c_currency_id = c_currency.c_currency_id 
               where hv_afgo_fundschedule.afgo_fund_id = activity.afgo_fund_id
               group by afgo_quarter.startdate, afgo_quarter.enddate, c_currency.iso_code
               order by afgo_quarter.startdate
            )
            loop
               p ('<budget type="1">');
               p ('<period-start iso-date="' || to_char (nvl(budget.p_startdate,sysdate), 'yyyy-mm-dd') || '"/>');
               p ('<period-end iso-date="' || to_char (nvl(budget.p_enddate,sysdate+1), 'yyyy-mm-dd') || '"/>');
               p ('<value currency="' || budget.p_currency || '" value-date="' || to_char (nvl(budget.p_startdate,sysdate), 'yyyy-mm-dd') || '">' || budget.p_sum || '</value>');
               p ('</budget>');
            end loop;

            --transaction incoming loop
            for transact_in in (
               select 
               hv_afgo_fundschedule.dateinvoiced as p_date,
               hv_afgo_fundschedule.description as p_description,
               c_currency.iso_code as p_currency,
               afgo_fund.referenceno as p_provider_act,
               sum(hv_afgo_fundschedule.invoicedamt) as p_sum
               from jasper.hv_afgo_fundschedule
               inner join afgo_quarter on jasper.hv_afgo_fundschedule.afgo_quarter_id = afgo_quarter.afgo_quarter_id
               inner join c_currency on hv_afgo_fundschedule.c_currency_id = c_currency.c_currency_id 
               inner join afgo_fund on hv_afgo_fundschedule.afgo_fund_id = afgo_fund.afgo_fund_id
               where 
               hv_afgo_fundschedule.afgo_fund_id = activity.afgo_fund_id
               and hv_afgo_fundschedule.dateinvoiced <= sysdate
               group by hv_afgo_fundschedule.dateinvoiced, hv_afgo_fundschedule.description, c_currency.iso_code, afgo_fund.referenceno
               order by  hv_afgo_fundschedule.dateinvoiced
            )
            loop
               p ('<transaction><transaction-type code="1" />');
               p ('<transaction-date iso-date="' || to_char (nvl(transact_in.p_date,sysdate), 'yyyy-mm-dd') || '"/>');
               p ('<value currency="' || transact_in.p_currency || '" value-date="' || to_char (nvl(transact_in.p_date,sysdate), 'yyyy-mm-dd') || '">' || transact_in.p_sum || '</value>');
               p ('<provider-org provider-activity-id="' || transact_in.p_provider_act || '" ref="XM-DAC-7" />');               
               p ('</transaction>');
            end loop;

            --transaction commitment loop
            for transact_co in (
               select 
               hv_afgo_fundschedule.dateinvoiced as p_date,
               hv_afgo_fundschedule.description as p_description,
               c_currency.iso_code as p_currency,
               afgo_fund.referenceno as p_provider_act,
               sum(hv_afgo_fundschedule.grandtotal) as p_sum
               from jasper.hv_afgo_fundschedule
               inner join afgo_quarter on jasper.hv_afgo_fundschedule.afgo_quarter_id = afgo_quarter.afgo_quarter_id
               inner join c_currency on hv_afgo_fundschedule.c_currency_id = c_currency.c_currency_id 
               inner join afgo_fund on hv_afgo_fundschedule.afgo_fund_id = afgo_fund.afgo_fund_id
               where 
               hv_afgo_fundschedule.afgo_fund_id = activity.afgo_fund_id
               group by hv_afgo_fundschedule.dateinvoiced, hv_afgo_fundschedule.description, c_currency.iso_code, afgo_fund.referenceno
               order by  hv_afgo_fundschedule.dateinvoiced
            )
            loop
               p ('<transaction><transaction-type code="2" />');
               p ('<transaction-date iso-date="' || to_char (nvl(transact_co.p_date,sysdate), 'yyyy-mm-dd') || '"/>');
               p ('<value currency="' || transact_co.p_currency || '" value-date="' || to_char (nvl(transact_co.p_date,sysdate), 'yyyy-mm-dd') || '">' || transact_co.p_sum || '</value>');
               p ('<provider-org provider-activity-id="' || transact_co.p_provider_act || '" ref="XM-DAC-7" />');               
               p ('</transaction>');
            end loop;
            
            p ('</iati-activity>');

         --generate child activities
         for childact in (
            --One projectcluser may have multiple fundallocations, what is the preferred relation between projectcluster and fund?
            --Adding distinct keyword in the meantime
            select distinct
            afgo_projectcluster.afgo_projectcluster_id as afgo_projectcluster_id,
            afgo_fundallocation.afgo_fund_id,
            (select referenceno from afgo_fund where afgo_fund_id = afgo_fundallocation.afgo_fund_id) as p_referenceno,
            afgo_projectcluster.updated as p_updated,
            afgo_projectcluster.name as p_title,
            (select textscoreb from jasper.hv_iati202_buza_vw where jasper.hv_iati202_buza_vw.afgo_projectcluster_id = afgo_projectcluster.afgo_projectcluster_id AND jasper.hv_iati202_buza_vw.afgo_criterium_id = '1002300') as p_description,
            afgo_projectcluster.startdate as p_datestart,
            afgo_projectcluster.enddate as p_dateend
            from afgo_projectcluster
            inner join afgo_fundallocation on afgo_projectcluster.afgo_projectcluster_id = afgo_fundallocation.afgo_projectcluster_id	
            where afgo_fundallocation.afgo_fund_id = activity.afgo_fund_id
            order by afgo_projectcluster.afgo_projectcluster_id
         )
      
         loop
            p ('<iati-activity xml:lang="en" last-updated-datetime="' || replace (to_char (childact.p_updated, 'yyyy-mm-dd hh24:mi:ss'), ' ', 'T') || 'Z">');
            p ('<iati-identifier>NL-KVK-41198677-AFGO_PROJECTCLUSTER-'|| childact.afgo_projectcluster_id ||'</iati-identifier>');
            p ('<reporting-org ref="NL-KVK-41198677" type="21"><narrative><![CDATA[Hivos]]></narrative></reporting-org>');
            p ('<title><narrative><![CDATA['|| nvl(childact.p_title,'Untitled activity') ||']]></narrative></title>');
            p ('<description><narrative><![CDATA[' || nvl(childact.p_description,'Undescribed activity') || ']]></narrative></description>');
            p ('<participating-org ref="NL-KVK-41198677" role="2" type="21"></participating-org>');
            --participating partners
            for partner in (
               select distinct hv_c_bpartner.name as p_name from jasper.hv_afgo_commitment 
               inner join jasper.hv_c_bpartner on jasper.hv_afgo_commitment.c_bpartner_id = jasper.hv_c_bpartner.c_bpartner_id
               where hv_afgo_commitment.afgo_projectcluster_id = childact.afgo_projectcluster_id
               order by 1
            )
            loop
               p ('<participating-org role="4"><narrative><![CDATA[' || partner.p_name || ']]></narrative></participating-org>');            
            end loop;   
            p ('<activity-status code="2" />');
            p ('<activity-date iso-date="' || to_char (nvl(childact.p_datestart,sysdate), 'yyyy-mm-dd') || '" type="1" />');
            p ('<activity-date iso-date="' || to_char (nvl(childact.p_dateend,sysdate+1), 'yyyy-mm-dd') || '" type="3" />');
            p ('<contact-info type="1"><telephone>0031703765500</telephone><email>info@hivos.org</email></contact-info>');
            --recipient country
            for recipient_co in (
               select name as p_code, integerscore as p_percentage from jasper.hv_iati202_buza_vw where 
               jasper.hv_iati202_buza_vw.afgo_projectcluster_id = childact.afgo_projectcluster_id 
               and jasper.hv_iati202_buza_vw.description = 'IATI Country' 
               and jasper.hv_iati202_buza_vw.integerscore <> 0 order by 1
            )
            loop
               p ('<recipient-country code="' || recipient_co.p_code || '" percentage="' || recipient_co.p_percentage || '" />');
            end loop;
            --recipient region
            for recipient_re in (
               select name as p_code, integerscore as p_percentage from jasper.hv_iati202_buza_vw where 
               jasper.hv_iati202_buza_vw.afgo_projectcluster_id = childact.afgo_projectcluster_id 
               and jasper.hv_iati202_buza_vw.description = 'IATI Region' 
               and jasper.hv_iati202_buza_vw.integerscore <> 0 order by 1
            )
            loop
               p ('<recipient-region code="' || recipient_re.p_code || '" percentage="' || recipient_re.p_percentage || '" />');
            end loop;
            --sector
            for sector in (
               select name as p_code, integerscore as p_percentage from jasper.hv_iati202_buza_vw where 
               jasper.hv_iati202_buza_vw.afgo_projectcluster_id = childact.afgo_projectcluster_id 
               and jasper.hv_iati202_buza_vw.description = 'IATI DAC'
               and jasper.hv_iati202_buza_vw.integerscore <> 0 order by 1
            )
            loop
               p ('<sector vocabulary="1" code="' || sector.p_code || '" percentage="' || sector.p_percentage || '" />');
            end loop;
            --policy marker
            for policy_marker in (
               select name as p_code, value as p_significance from jasper.hv_iati202_buza_vw where 
               jasper.hv_iati202_buza_vw.afgo_projectcluster_id = childact.afgo_projectcluster_id 
               and jasper.hv_iati202_buza_vw.description = 'IATI policymarker'
               and cast(regexp_replace(jasper.hv_iati202_buza_vw.value, '[^0-9]+', '') as number) <> 0
               order by 1
            )
            loop
               p ('<policy-marker vocabulary="1" code="' || policy_marker.p_code || '" significance="' || policy_marker.p_significance || '" />');
            end loop;
            p ('<default-flow-type code="30" />');
            p ('<default-finance-type code="110" />');
            p ('<default-aid-type code="C01" />');
            p ('<default-tied-status code="5" />');
            --transaction disbursement and expenditure loop
            for transact_disb_exp in (
               select hivo_rv_commitmentallocation.datetrx as p_date, hivo_rv_commitmentallocation.description as p_description, hv_c_bpartner.name as p_name, c_currency.iso_code as p_currency, hivo_rv_commitmentallocation.payamt as p_value from jasper.hv_afgo_commitment 
               inner join jasper.hv_c_bpartner on hv_afgo_commitment.c_bpartner_id = hv_c_bpartner.c_bpartner_id
               inner join hivo_rv_commitmentallocation on hv_afgo_commitment.afgo_commitment_id = hivo_rv_commitmentallocation.afgo_commitment_id
               inner join c_currency on hivo_rv_commitmentallocation.c_currency_id = c_currency.c_currency_id 
               inner join c_invoice on jasper.hv_afgo_commitment .afgo_commitment_id = c_invoice.afgo_commitment_id
               inner join c_invoiceline on c_invoice.c_invoice_id = c_invoiceline.c_invoice_id
               inner join afgo_fundallocation on c_invoiceline.c_invoiceline_id = afgo_fundallocation.c_invoiceline_id               
               where
               hv_afgo_commitment.afgo_projectcluster_id = childact.afgo_projectcluster_id
               and afgo_fundallocation.afgo_fund_id = childact.afgo_fund_id
               and hivo_rv_commitmentallocation.datetrx <= sysdate
               order by hivo_rv_commitmentallocation.datetrx, hivo_rv_commitmentallocation.payamt
            )
            loop
               p ('<transaction><transaction-type code="3" />');
               p ('<transaction-date iso-date="' || to_char (nvl(transact_disb_exp.p_date,sysdate), 'yyyy-mm-dd') || '"/>');
               p ('<value currency="' || transact_disb_exp.p_currency || '" value-date="' || to_char (nvl(transact_disb_exp.p_date,sysdate), 'yyyy-mm-dd') || '">' || transact_disb_exp.p_value || '</value>');
               p ('<receiver-org><narrative><![CDATA[' || transact_disb_exp.p_name || ']]></narrative></receiver-org>');
               p ('</transaction>');
            end loop;

            --transaction incoming commitment loop
            for transact_incoming_com in (
               select a.p_date, a.p_description, a.afgo_fund_id, a.p_currency, a.p_value, b.referenceno as p_referenceno from (
               select afgo_commitmentline.updated as p_date, afgo_commitmentline.description as p_description, max(afgo_fundallocation.afgo_fund_id) as afgo_fund_id, c_currency.iso_code as p_currency, afgo_commitmentline.linenetamt as p_value from jasper.hv_afgo_commitment
               inner join afgo_commitmentline on hv_afgo_commitment.afgo_commitment_id = afgo_commitmentline.afgo_commitment_id
               inner join afgo_fundallocation on afgo_commitmentline.afgo_commitmentline_id = afgo_fundallocation.afgo_commitmentline_id
               inner join c_currency on hv_afgo_commitment.c_currency_id = c_currency.c_currency_id 
               where hv_afgo_commitment.afgo_projectcluster_id = childact.afgo_projectcluster_id
               and afgo_fund_id = childact.afgo_fund_id
               group by afgo_commitmentline.updated, afgo_commitmentline.description, c_currency.iso_code, afgo_commitmentline.linenetamt
               order by afgo_commitmentline.updated, afgo_commitmentline.linenetamt
               ) a, afgo_fund b where a.afgo_fund_id = b.afgo_fund_id
            )
            loop
               p ('<transaction><transaction-type code="11" />');
               p ('<transaction-date iso-date="' || to_char (nvl(transact_incoming_com.p_date,sysdate), 'yyyy-mm-dd') || '"/>');
               p ('<value currency="' || transact_incoming_com.p_currency || '" value-date="' || to_char (nvl(transact_incoming_com.p_date,sysdate), 'yyyy-mm-dd') || '">' || transact_incoming_com.p_value || '</value>');
               p ('<provider-org provider-activity-id="NL-KVK-41198677-AFGO_FUND-' || transact_incoming_com.p_referenceno || '" ref="NL-KVK-41198677" />');               
               p ('</transaction>');
            end loop;

            p ('<related-activity ref="NL-KVK-41198677-AFGO_FUND-' || childact.p_referenceno || '" type="1" />');
            
            --result loop
            --order by not possible in distinct http://docs.oracle.com/javadb/10.5.3.0/ref/rrefsqlj13658.html
            for result_loop in (
               select distinct a.afgo_criteriumset_id, a.setdescription as p_type, a.sethelp as p_title, a.setnote as p_description 
               from jasper.hv_iati202_buza_vw a where 
               a.afgo_projectcluster_id = childact.afgo_projectcluster_id 
               and a.description = 'IATI indicator'
            )
            loop
               p ('<result type="'|| result_loop.p_type ||'" aggregation-status="0">');
               p ('<title><narrative><![CDATA[' || result_loop.p_title || ']]></narrative></title>');
               p ('<description><narrative><![CDATA[' || result_loop.p_description || ']]></narrative></description>');
               
               for indicator_loop in (
                  select distinct a.afgo_criterium_id, a.measure as measure, a.help as p_title, a.documentnote as p_description 
                  from jasper.hv_iati202_buza_vw a where 
                  a.afgo_projectcluster_id = childact.afgo_projectcluster_id 
                  and a.afgo_criteriumset_id = result_loop.afgo_criteriumset_id
                  and a.description = 'IATI indicator'                 
               )
               loop
                  p ('<indicator measure="' || indicator_loop.measure || '" ascending="1">');
                  p ('<title><narrative><![CDATA[' || indicator_loop.p_title || ']]></narrative></title>');
                  p ('<description><narrative><![CDATA[' || indicator_loop.p_description || ']]></narrative></description>');                  

                  for indicator_value_loop in (
                     select a.afgo_scheduleitem_name, extract (year from a.datedoc) as p_year, a.longdescriptionb as p_description, a.numericscore || a.integerscore as p_value, a.afgo_criterium_id, a.afgo_scheduleitem_id
                     from jasper.hv_iati202_buza_vw a where 
                     a.afgo_projectcluster_id = childact.afgo_projectcluster_id 
                     and a.afgo_criteriumset_id = result_loop.afgo_criteriumset_id
                     and a.afgo_criterium_id = indicator_loop.afgo_criterium_id
                     and a.description = 'IATI indicator'                                             
                     order by decode(a.afgo_scheduleitem_name, 'IATI all baseline data', 1, 'IATI results target data', 2, 'IATI results actual data', 3, 4)
                  )
                  loop
                     if (indicator_value_loop.afgo_scheduleitem_name = 'IATI all baseline data') then
                        p ('<baseline year="' || indicator_value_loop.p_year || '" value="' || indicator_value_loop.p_value || '">');
                        p ('<comment><narrative><![CDATA[' || indicator_value_loop.p_description || ']]></narrative></comment>');
                        p ('</baseline>');
                     elsif (indicator_value_loop.afgo_scheduleitem_name = 'IATI results target data') then
                        p ('<period>');
                        p ('<period-start iso-date="' || to_char (nvl(childact.p_datestart,sysdate), 'yyyy-mm-dd') || '" />');
                        p ('<period-end iso-date="' || to_char (nvl(childact.p_dateend,sysdate), 'yyyy-mm-dd') || '" />');
                        p ('<target value="' || indicator_value_loop.p_value || '">');
                        p ('<comment><narrative><![CDATA[' || indicator_value_loop.p_description || ']]></narrative></comment>');
                        p ('</target></period>');
                     else   
                        p ('<period>');
                        p ('<period-start iso-date="' || to_char (nvl(childact.p_datestart,sysdate), 'yyyy-mm-dd') || '" />');
                        p ('<period-end iso-date="' || to_char (nvl(childact.p_dateend,sysdate), 'yyyy-mm-dd') || '" />');
                        p ('<actual value="' || indicator_value_loop.p_value || '">');
                        p ('<comment><narrative><![CDATA[' || indicator_value_loop.p_description || ']]></narrative></comment>');
                        p ('</actual></period>');
                     end if;
                  end loop;
                  p ('</indicator>');
               end loop;
               
               p ('</result>');
            end loop;            
            p ('</iati-activity>');
            end loop;
            
         end loop;
         
         p ('</iati-activities>');
         clobtofile ('iati202buza.xml', 'HV_XMLDIR', ll_xml);      
      end mainprogram;
   end hv_iati202_buza; 
/

exec jasper.hv_iati202_buza.mainprogram;