# sdb-consistency-checker
# Consistency Checker Tool for SingleStore

Usage: ./memsql_consistency_checker.sh [-u MASTERUSER] [-p MASTERPASS] [-h MASTERHOST] [-d DATABASE]...
Check tables and schemas across aggregators and leafs for consistency
We assume that Leaf User/Password is consistent across Leaves
 
    -?,--help       display this help and exit
    -h,--hostname   the master aggregator hostname, defaults to 127.0.0.1
    -lu,--leafuser  the user for the leafs, defaults to --user
    -lp,--leafpass  the password for the leafs, defaults to --pass
    -d,--database   run the consistency check only against specified db
    -p,--password   the password for the master aggregator if necessary
    -P,--port       the port for the master aggregator, defaults to 3306
    -u,--user       the user for the master aggregator, defaults to cur user
    -v              verbose mode. Can be used multiple times for increased
                    verbosity.
