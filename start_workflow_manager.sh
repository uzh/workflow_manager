#!/usr/bin/bash
source /usr/local/ngseq/etc/lmod_profile
module load Dev/Ruby/3.2.3
module load Tools/Redis/7.2.4
. "/usr/local/ngseq/miniconda3/etc/profile.d/conda.sh"
conda activate gtools_env
which python
which g-sub
which g-req
mkdir -p logs
mkdir -p dbs
bundle exec workflow_manager -d druby://fgcz-h-031:40001
