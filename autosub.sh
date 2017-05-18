#!/bin/bash
#
# Submit and automatically resubmit jobs as needed
# - customize your job submission in newjob()
#
# Author: Eliot Quon, May 2017
#
set -e
JOBLOGDIR=$HOME/current_jobs

newjob()
{
    # process parameters for this job
    simdate=$1
    newjobscript="submit_wrf_$simdate.sh"

    echo $newjobscript
    if [ -f "$newjobscript" ]; then
        # this is a restart of an existing run
        echo $newjobscript >> restarts
        exit
    else
        # run failure was probably a fluke
        rm -f restarts
    fi

    # TODO: optional job preprocessing here
    cp namelist.input.$simdate namelist.input

    # TODO: now create a custom script for this job
    cat > $newjobscript << END_OF_JOB_SCRIPT

#!/bin/bash -l

# Specify the name of the job
#PBS -N MexicoWRFJan
#PBS -l walltime=48:00:00
#PBS -l nodes=16
#PBS -o wrf.log
#PBS -e wrf.err
#PBS -m abe
#PBS -M caroline.draxl@nrel.gov
#PBS -A wrfnaris 
#PBS -q batch-h

cd $PBS_O_WORKDIR

echo $PBS_O_WORKDIR
pwd


ulimit -s unlimited


 module purge
 module use /nopt/nrel/apps/modules/default/modulefiles
 module load impi-intel
 module load libraries/netcdf
 module load libraries/pnetcdf
 module load wrf 

 module list

echo original striping for /scratch/cdraxl/Mexico/real/20130514
lfs getstripe -d .
echo setting striping for /scratch/cdraxl/Mexico/real/20130514 to 4
lfs setstripe -c 4 .

/bin/rm rsl.*

mpirun  -np 384 -envall /home/cdraxl/WRFV3.7.1_TEND_MMC/main/wrf.exe >& run_wrf.log
 sync


exit 0

END_OF_JOB_SCRIPT
}

#
# Script execution starts here
#
if [ -f "currentRun" ]; then
    runID=`cat currentRun`
    if [ "$runID" -le "`wc -l runParams | awk '{print $1}'`" ]; then
        # continue simulation series
        curdir=$PWD
        params=`head -n $runID runParams | tail -n 1`

        # submit new job from the original submission directory
        cd `cat submitDir`
        jobscript=`newjob $params`
        jobID=`qsub $jobscript`
        cd $curdir

    else
        # all done!
        echo 'Finished with simulation series:'
        cat jobHistory

        curdir=$PWD
        cd ..
        mv $curdir $JOBLOGDIR/archive/

        exit 0
    fi

else
    if [ -z "$1" ]; then
        echo "Specify parameter(s) for each desired simulation in a sequence"
        echo "Multiple parameters for a single simulation may be specified in quotes"
        exit 0
    fi

    # initial setup
    mkdir -p $JOBLOGDIR/archive

    # save command line parameters
    for param in "$@"; do
        echo $param >> runParams
    done

    # submit the job
    runID=1
    params=`head -n 1 runParams`
    jobscript=`newjob $params`
    jobID=`qsub $jobscript`
    if [ "$?" -eq 0 ]; then
        #- SUCCESS
        curDirName="${PWD##*/}"
        jobDir="$JOBLOGDIR/${curDirName}_${jobID}" # create a unique case name
        mkdir $jobDir

        echo $PWD > $jobDir/submitDir

        # save parameters for restarts
        mv runParams $jobDir/

        # save this script for resubmission
        cp $0 $jobDir/resubmit.sh

        cd $jobDir

    else
        #- FAIL
        echo 'Problem with job submission!'
        exit 99
    fi
fi

echo $runID > currentRun
echo "$runID $jobID $jobscript `date`" >> jobHistory

