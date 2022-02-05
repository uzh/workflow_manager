#!/usr/bin/bash
source /usr/local/ngseq/etc/lmod_profile
module load Dev/Ruby/3.0.3
module load Tools/Redis/6.0.1
conda activate gtools_env
which python
which g-sub
which g-req
mkdir -p logs
mkdir -p dbs
bundle exec workflow_manager -d druby://fgcz-h-031:40001
