[[ $(basename $0) =~ run-compose--(.*).sh ]]
export RUN_ENV=${BASH_REMATCH[1]}
export COMPOSE_PROJECT_NAME=$(basename `pwd` | sed 's/-/_/g')_${RUN_ENV}_

docker-compose \
-f compose/docker-compose.yml \
-f compose/docker-compose.${RUN_ENV}.yml \
$@