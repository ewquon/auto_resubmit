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

#-------------------------------
# Options (TODO: Customize this as necessary)
checkInterval=1 # seconds
maxResubmits=3

checkFinishedOK()
{
    # Can leave this function empty...
    # the script will check for the last $?
    tail outputfile | grep 'SUCCESS' &> /dev/null
}
#-------------------------------

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

        checkjob $jobID &> /dev/null
        if [ "$?" -ne 0 ]; then
            # job no longer exists
            exitcode=`/nopt/moab/tools/moab/showhist.moab.pl -n 5 $jobID | grep 'Exit Code' | awk '{print $NF}'`
            if [ "$exitcode" -eq 0 ]; then
                checkFinishedOK # may update $?
                if [ "$?" -eq 0 ]; then
                    runID=$((runID+1))
                    echo "[`date`] Submitting next job in `cat submitDir` (run=$runID)"
                    echo $runID > currentRun
                fi
            fi

            # resubmit
            echo "[`date`] Resubmitting job in `cat submitDir`"
            ./resubmit.sh 
        fi
    done

    sleep $checkInterval
done

