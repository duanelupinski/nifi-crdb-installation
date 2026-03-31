#to import values for parameters, run this script with the following command:
#source mssql-config-params.sh

CTX='2ad6fae4-019d-1000-11fd-d9d504a24ea3'
BASE='docker exec -it nifi126 /opt/nifi/nifi-toolkit-current/bin/cli.sh nifi'
URL='https://120ebb7486d1:8443'
TS='/opt/nifi/nifi-current/conf/truststore.p12'
TSP='xxxxxxxxxxxxxxxxxxxxxxxx'

$BASE set-param -u "$URL" -ts "$TS" -tst PKCS12 -tsp "$TSP" -btk "$TOKEN" -pcid "$CTX" -pn database_host -pv 'dlupinski-sandbox-sqlsvr.public.d4ebc4874999.database.windows.net' -ps false
$BASE set-param -u "$URL" -ts "$TS" -tst PKCS12 -tsp "$TSP" -btk "$TOKEN" -pcid "$CTX" -pn database_port -pv '3342' -ps false
$BASE set-param -u "$URL" -ts "$TS" -tst PKCS12 -tsp "$TSP" -btk "$TOKEN" -pcid "$CTX" -pn database_name -pv 'northwind' -ps false
$BASE set-param -u "$URL" -ts "$TS" -tst PKCS12 -tsp "$TSP" -btk "$TOKEN" -pcid "$CTX" -pn database_user -pv 'duane' -ps false
$BASE set-param -u "$URL" -ts "$TS" -tst PKCS12 -tsp "$TSP" -btk "$TOKEN" -pcid "$CTX" -pn database_password -pv "$PASSWD" -ps true
$BASE set-param -u "$URL" -ts "$TS" -tst PKCS12 -tsp "$TSP" -btk "$TOKEN" -pcid "$CTX" -pn database_driver_class_name -pv 'com.microsoft.sqlserver.jdbc.SQLServerDriver' -ps false
$BASE set-param -u "$URL" -ts "$TS" -tst PKCS12 -tsp "$TSP" -btk "$TOKEN" -pcid "$CTX" -pn database_driver_location -pv '/opt/nifi/nifi-current/lib/mssql-jdbc-13.4.0.jre11.jar' -ps false
$BASE set-param -u "$URL" -ts "$TS" -tst PKCS12 -tsp "$TSP" -btk "$TOKEN" -pcid "$CTX" -pn database_connection_url -pv 'jdbc:sqlserver://;serverName=dlupinski-sandbox-sqlsvr.public.d4ebc4874999.database.windows.net;port=3342;databaseName=northwind' -ps false
