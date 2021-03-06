## Check whether there are three high_value with same value for three different tables with the status='IMPORTED' or status like 'CLEAR%'
tmpfile=analyzing.tmp
sqlplus -s uxinsight/oracle123 <<! |awk '{if(NF>0 && $1!="HOST_NAME" && substr($1,1,1) !="-")print $1" "$2}' >$tmpfile
	set feedback off
	set heading off
	set pages 999
	set lines 300

	select host_name, high_value from 
	(select host_name, high_value, count(distinct table_name) cnt
	 from bidata_parts_status where status='IMPORTED' or status like 'CLEAR%' 
	 group by host_name, high_value)
	where cnt=3;
!
hvs=`cat $tmpfile|awk '{if($1=="ruei32")print $2}'`
host_name="ruei32"
for high_value in `echo $hvs` ; do
echo "Analyzing $high_value"
sqlplus -s 'uxinsight/oracle123' <<!
	update bidata_parts_status set status='ANALYZING', start_analysis_time=sysdate 
	where (status='IMPORTED' or status like 'CLEAR%') and host_name='$host_name' and high_value='$high_value';
	commit;
!

tmp_table_name=RUEI_$high_value

extabs=`sqlplus -s uxinsight/oracle123 <<!|awk '{if(NF>0 && $1!="EXCHANGE_TABLE" && substr($1,1,1) !="-")print $1}'
	set feedback off
	set heading off
	set pages 999
	set lines 300
	select distinct exchange_table from bidata_parts_status t 
	where high_value='$high_value' and (status='IMPORTED' or status like 'CLEAR%')
	and job_time=(select max(job_time) from bidata_parts_status where exchange_table = t.exchange_table) order by 1;
!`

echo $extabs
master_table=`echo $extabs|awk '{print $1}'`
proper_table=`echo $extabs|awk '{print $2}'`
userfl_table=`echo $extabs|awk '{print $3}'`

echo $master_table
echo $proper_table
echo $userfl_table

echo "Create tmp table $tmp_table_name"

sqlplus -s uxinsight/oracle123 <<!

alter session enable parallel dml;
alter session enable parallel ddl;

create table $tmp_table_name as
select /*+ parallel(a,12) parallel(b,6)*/
to_date('197001010800','yyyymmddhh24mi')+a.PERIOD_ID/1440 ctime,
a.page_load_time, a.dynamic_network_time network_response, a.dynamic_server_time server_response, 
a.pageview_id, a.client_ip, a.user_id, b.NAME uf_name, b.step
from $master_table a,  $userfl_table b
where a.PERIOD_ID=b.PERIOD_ID(+) and a.pageview_id=b.pageview_id(+)
;

--echo "Generating Data from tmp table"

insert into businesses
select /*+ parallel(t,12) parallel(c,12)*/ 
'$high_value', (select to_date('19700101','yyyymmdd') + $high_value /1440 - 1 from dual) , 
(select to_date('1970010108','yyyymmddhh24') + $high_value /1440 - 1 from dual),
(select to_date('1970010118','yyyymmddhh24') + $high_value /1440 - 1 from dual), 
c.region_name,
round(avg(decode(t.UF_NAME,'包月量查询',t.page_load_time,null)/1000),2) 包月量查询,
round(avg(decode(t.UF_NAME,'补卡',t.page_load_time,null)/1000),2) 补卡,
round(avg(decode(t.UF_NAME,'查询个人客户资料',t.page_load_time,null)/1000),2) 查询个人客户资料,
round(avg(decode(t.UF_NAME,'查询用户资料',t.page_load_time,null)/1000),2) 查询用户资料,
round(avg(decode(t.UF_NAME,'产品变更',t.page_load_time,null)/1000),2) 产品变更,
round(avg(decode(t.UF_NAME,'登录',t.page_load_time,null)/1000),2) 登录,
round(avg(decode(t.UF_NAME,'改付费计划',t.page_load_time,null)/1000),2) 改付费计划,
round(avg(decode(t.UF_NAME,'改密码',t.page_load_time,null)/1000),2) 改密码,
round(avg(decode(t.UF_NAME,'改资料',t.page_load_time,null)/1000),2) 改资料,
round(avg(decode(t.UF_NAME,'个人客户开户',t.page_load_time,null)/1000),2) 个人客户开户,
round(avg(decode(t.UF_NAME,'过户',t.page_load_time,null)/1000),2) 过户,
round(avg(decode(t.UF_NAME,'积分查询',t.page_load_time,null)/1000),2) 积分查询,
round(avg(decode(t.UF_NAME,'缴费',t.page_load_time,null)/1000),2) 缴费,
round(avg(decode(t.UF_NAME,'缴费回退',t.page_load_time,null)/1000),2) 缴费回退,
round(avg(decode(t.UF_NAME,'梦网业务订购或取消',t.page_load_time,null)/1000),2) 梦网业务订购或取消,
round(avg(decode(t.UF_NAME,'停开机',t.page_load_time,null)/1000),2) 停开机,
round(avg(decode(t.UF_NAME,'详单查询',t.page_load_time,null)/1000),2) 详单查询,
round(avg(decode(t.UF_NAME,'用户资料变更',t.page_load_time,null)/1000),2) 用户资料变更,
round(avg(decode(t.UF_NAME,'余额查询',t.page_load_time,null)/1000),2) 余额查询,
round(avg(decode(t.UF_NAME,'账单查询',t.page_load_time,null)/1000),2) 账单查询
from $tmp_table_name t, data_client_info c
where to_number(to_char(t.ctime,'hh24'),'99') between 8 and 18
and (lower(substr(t.user_id,1,8))=lower(substr(c.user_id,1,8)))
and c.is_main='是' 
and  t.step in ('查询','查询明细话单','提交','选择验证方式','签入','显示客户资料','点击提交')
group by c.region_name
order by 1;

commit;

insert into business_halls
select /*+ parallel(t,12) parallel(c,12)*/ 
'$high_value', (select to_date('19700101','yyyymmdd') + $high_value /1440 - 1 from dual) ,
(select to_date('1970010108','yyyymmddhh24') + $high_value /1440 - 1 from dual),
(select to_date('1970010118','yyyymmddhh24') + $high_value /1440 - 1 from dual),
c.region_name, c.business_hall, c.is_main,
round(avg(t.page_load_time)/1000,2) page_load_time,
round(avg(t.network_response)) network_response,
round(avg(t.server_response)) server_response,
count(distinct t.pageview_id) pageviews,
count(distinct t.client_ip) clients,
count(distinct t.user_id) users
from $tmp_table_name t, data_client_info c
where to_number(to_char(t.ctime,'hh24'),'99') between 8 and 18
and lower(substr(t.user_id,1,8))=lower(substr(c.user_id,1,8))
group by c.region_name, c.business_hall,c.is_main
order by 1,2;

commit;
!
echo "DONE"
sqlplus -s 'uxinsight/oracle123' <<!
	update bidata_parts_status set status='ANALYZED', start_analysis_time=sysdate 
	where (status='IMPORTED' or status like 'CLEAR%') and host_name='$host_name' and high_value='$high_value';
	commit;
!

## Clear local database

done

## Clear work area
rm -f $tmpfile
