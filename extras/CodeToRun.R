library(glp1Hira)

# Optional: specify where the temporary files (used by the Andromeda package) will be created:
options(andromedaTempFolder = "")

# Maximum number of cores to be used:
maxCores <- parallel::detectCores()

# The folder where the study intermediate and result files will be written:
outputFolder <- ""

# Details for connecting to the server:
connectionDetails <- DatabaseConnector::createConnectionDetails(dbms = "pdw",
                                                                server = Sys.getenv("PDW_SERVER"),
                                                                user = NULL,
                                                                password = NULL,
                                                                port = Sys.getenv("PDW_PORT"))

# The name of the database schema where the CDM data can be found:
cdmDatabaseSchema <- ""

# The name of the database schema and table where the study-specific cohorts will be instantiated:
cohortDatabaseSchema <- ""
cohortTable <- ""

# Some meta-information that will be used by the export function:
databaseId <- ""
databaseName <- ""
databaseDescription <- ""

# For Oracle: define a schema that can be used to emulate temp tables:
oracleTempSchema <- NULL

# Delete the cohort 2672
sql = "delete from @cohortDatabaseSchema.@cohortTable where cohort_definition_id = 2672;"
sql = SqlRender::render(sql, 
                        cohortDatabaseSchema = cohortDatabaseSchema,
                        cohortTable = cohortTable)
sql = SqlRender::translateSql(sql = sql, targetDialect = 'Oracle', oracleTempSchema = oracleTempSchema)
DatabaseConnector::executeSql(conn, sql)

# Recreate the cohort 2672
sql = SqlRender::readSql(file.path(getwd(), 'inst/sql/sql_server/PCH_T2DM__SGLT2i_new_user_main_vs_GLP1a.sql'))
sql = SqlRender::render(sql, 
                        cdm_database_schema = cdmDatabaseSchema,
                        vocabulary_database_schema = cdmDatabaseSchema,
                        target_database_schema = cohortDatabaseSchema,
                        target_cohort_table = cohortTable,
                        target_cohort_id = 2672)
sql = SqlRender::translate(sql = sql, targetDialect = 'oracle', oracleTempSchema = oracleTempSchema)
DatbaseConnector::executeSql(conn, sql)

# Remove insulin exposure in each target/comparator cohorts
sql = 'select person_id, drug_exposure_start_date into #insulinPatients 
from @cdmDatabaseSchema.drug_exposure
where drug_concept_id in (select distinct descendant_concept_id from @vocabularyDatabaseSchema.concept_ancestor where ancestor_concept_id in (21600713, 1596977));

select *, 
case when c.cohort_start_date >= ip.drug_exposure_start_date and ip.drug_exposure_start_date + 365 > c.cohort_start_date then 1
else 0
end as exclude
into #insulinInCohort 
from (select * from @cohortDatabaseSchema.@cohortTable 
where cohort_definition_id in (2683, 2672, 2742, 2743, 2744, 2745, 2747, 2748, 2766, 2767, 2752, 2746, 2755, 2754, 2741, 2787, 3965, 3966, 3967, 3968)) c 
left join #insulinPatients ip 
on c.subject_id = ip.person_id; 

delete from @cohortDatabaseSchema.@cohortTable where cohort_definition_id in (2683, 2672, 2742, 2743, 2744, 2745, 2747, 2748, 2766, 2767, 2752, 2746, 2755, 2754, 2741, 2787, 3965, 3966, 3967, 3968);
insert into @cohortDatabaseSchema.@cohortTable select cohort_definition_id, subject_id, cohort_start_date, cohort_end_date from #insulinInCohort where exclude = 0;

truncate table #insulinPatients;
truncate table #insulinInCohort;
drop table #insulinPatients;
drop table #insulinInCohort;
'

sql = SqlRender::render(sql, 
                        cdmDatabaseSchema = cdmDatabaseSchema,
                        vocabularyDatabaseSchema = cdmDatabaseSchema,
                        cohortDatabaseSchema = cohortDatabaseSchema,
                        cohortTable = cohortTable)

sql = SqlRender::translate(sql, targetDialect = 'oracle', oracleTempSchema = oracleTempSchema)
DatabaseConnector::executeSql(conn, sql)


execute(connectionDetails = connectionDetails,
        cdmDatabaseSchema = cdmDatabaseSchema,
        cohortDatabaseSchema = cohortDatabaseSchema,
        cohortTable = cohortTable,
        oracleTempSchema = oracleTempSchema,
        outputFolder = outputFolder,
        databaseId = databaseId,
        databaseName = databaseName,
        databaseDescription = databaseDescription,
        createCohorts = FALSE,
        synthesizePositiveControls = FALSE,
        runAnalyses = TRUE,
        packageResults = TRUE,
        maxCores = maxCores)

resultsZipFile <- file.path(outputFolder, "export", paste0("Results_", databaseId, ".zip"))
dataFolder <- file.path(outputFolder, "shinyData")

# You can inspect the results if you want:
prepareForEvidenceExplorer(resultsZipFile = resultsZipFile, dataFolder = dataFolder)
launchEvidenceExplorer(dataFolder = dataFolder, blind = TRUE, launch.browser = FALSE)

# Upload the results to the OHDSI SFTP server:
privateKeyFileName <- ""
userName <- ""
uploadResults(outputFolder, privateKeyFileName, userName)
