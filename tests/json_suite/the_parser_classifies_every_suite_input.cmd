The validator parses every input of the pinned JSONTestSuite corpus, and each
verdict matches the input's class in classification.tsv: an accepted document
exits 0 and a rejected one exits 1. Any other status, such as a file failure
reported for bytes that are not UTF-8, is a wrong verdict.

  $ linea build "$LINEA_ROOT"/tests/json_suite/validate.lin -o validate
  $ mkdir corpus && tar -xzf "$LINEA_ROOT"/tests/json_suite/parsing.tar.gz -C corpus
  $ grep -v '^#' "$LINEA_ROOT"/tests/json_suite/classification.tsv > classes

The classification names every input, and no other file.

  $ cut -f1 classes | sort > named
  $ ls corpus | sort | diff named -

Each input is validated once and its exit status compared with its class.

  $ accepted=0 rejected=0 wrong=0
  > tab=$(printf '\t')
  > while IFS="$tab" read -r name class policy; do
  >   reason=$(./validate corpus/"$name" 2>&1)
  >   status=$?
  >   case "$class:$status" in
  >     accept:0) accepted=$((accepted + 1)) ;;
  >     reject:1) rejected=$((rejected + 1)) ;;
  >     *) wrong=$((wrong + 1)); echo "$name: exit $status, expected $class ($policy): $reason" ;;
  >   esac
  > done < classes
  > echo "$accepted accepted, $rejected rejected, $wrong wrong"
  > test "$wrong" -eq 0
  103 accepted, 215 rejected, 0 wrong
