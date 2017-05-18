#!/bin/bash
#
# Submit and automatically resubmit jobs as needed
# - companion monitor script to run in the background
# - modify finishedOK function if needed
#
# Author: Eliot Quon, May 2017
#
set -e
LOCKDIR=${HOME}/.jobmon_is_running
JOBLOGDIR=${HOME}/current_jobs

#----------------------------------------------------------
# Options (TODO: Customize this as necessary)
checkInterval=60 # seconds
maxResubmits=3
myEmail='eliot.quon@nrel.gov'

checkFinishedOK()
{
    # TODO: Additional checks for successful job completion (optional)
    # Can leave this function empty... the script will check the last $?
    tail outputfile | grep 'SUCCESS' &> /dev/null
}

jobFailAlert()
{
    # TODO: Can send an email alert (optional)
    jobname=$1
    submitdir=$2
    echo "$jobname series in $submitdir failed after $maxResubmits resubmissions" | \
        mailx -s "$jobname failed" $myEmail
}
#----------------------------------------------------------

function cleanup()
{
    rmdir $LOCKDIR
    ret=$?
    if [ "$ret" -ne 0 ]; then
        echo "Problem removing lock directory ($ret)" >&2
    else
        echo "Job monitor shutdown successfully."
    fi
    exit $ret
}

# Lock directory reference:
# https://unix.stackexchange.com/questions/48505/how-to-make-sure-only-one-instance-of-a-bash-script-runs
mkdir $LOCKDIR &> /dev/null
if [ "$?" -eq 0 ]; then
    # Ensure that we grabbed a lock, and we can release it 
    # if SIGTERM or SIGINT(Ctrl-C) occurs.
    trap "cleanup" EXIT
else
    echo "Could not create lock directory '$LOCKDIR'"
    echo "Is $0 already running?"
    exit 1
fi

#
# Script execution starts here
#
while true; do

    for dname in $JOBLOGDIR/*; do
        if [ "${dname##*/}" == 'archive' ]; then continue; fi

        cd $dname
        latest=`tail -n 1 jobHistory`
        runID=`cat currentRun`
        jobID=`echo $latest | awk '{print $2}'`
        jobname=${PWD##*/} # job name is the directory name
        jobname=${jobname%_*} # strip the jobID from the name
        submitdir=`cat submitDir`

        if [ ! -d "$submitdir" ]; then
            echo "[`date`] $jobname : Directory not found; archiving simulation series"
            mv -v $dname $JOBLOGDIR/archive/
        fi

        checkjob $jobID &> /dev/null
        if [ "$?" -ne 0 ]; then
            #- Job no longer exists
            exitcode=`/nopt/moab/tools/moab/showhist.moab.pl -n 5 $jobID | grep 'Exit Code' | awk '{print $NF}'`
            if [ "$exitcode" -eq 0 ]; then
                checkFinishedOK # this function may or may not update "$?"
                if [ "$?" -eq 0 ]; then
                    runID=$((runID+1))
                    echo "[`date`] $jobname : UPDATING run ID to $runID"
                    echo $runID > currentRun
                fi
            fi

            #- Now resubmit (if we haven't reached our maximum number of restarts)
            #  Note: If the simulation series is complete, the resubmit.sh will move the directory
            #        to the archive
            if [ -f "$submitdir/restarts" ]; then
                Nrestarts=`wc -l ${submitdir}/restarts | awk '{print $1}'`
            else
                Nrestarts=0
            fi
            if [ "$Nrestarts" -ge "$maxResubmits" ]; then
                echo "[`date`] $jobname : Job has already been restarted $Nrestarts times; giving up and archiving simulation series"
                mv -v $dname $JOBLOGDIR/archive/
                jobFailAlert $jobname $submitdir
            else
                echo "[`date`] $jobname : RESUBMITTING job in $submitdir"
                ./resubmit.sh 
            fi

        else
            #- Job was found, i.e., it's either still running or queued.
            echo "[`date`] $jobname : Still in queue..."
        fi
    done

    sleep $checkInterval
done

