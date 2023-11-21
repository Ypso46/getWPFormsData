#!/bin/bash
set -e -x
# usage: ./getWPFormsInfo | tee test.csv
input="urlsWithoutZeroForms.txt"
echo "path|formID|postTitle|hasUploadField|hasPayOnline|payOnlineID|payOnlineIDnumberOfEntries|"
while IFS= read -r path
do
  formIDs=$(ssh -n wwp-prod -- "wp db query --path=$path 'SELECT ID FROM wp_posts wp WHERE wp.post_type='\''wpforms'\'' AND wp.post_status='\''publish'\'';' --skip-column-names;" 2>/dev/null)
  for formID in $formIDs; do 
    postTitle=$(ssh -n wwp-prod -- "wp db query --path=$path 'SELECT post_title FROM wp_posts wp WHERE wp.ID=$formID;' --skip-column-names;" 2>/dev/null)
    hasUploadField=$(ssh -n wwp-prod -- "wp db query --path=$path 'SELECT (SELECT CASE WHEN EXISTS (SELECT post_title FROM wp_posts wp WHERE wp.ID=$formID AND post_content LIKE '\''%type\":\"file-upload%'\'')	THEN 'TRUE' ELSE 'FALSE' END) as hasUploadField FROM wp_posts wp WHERE wp.ID=$formID;' --skip-column-names;" 2>/dev/null)
    hasPayOnline=$(ssh -n wwp-prod -- "wp db query --path=$path 'SELECT (SELECT CASE WHEN EXISTS (SELECT post_content FROM wp_posts wp WHERE wp.ID=$formID AND post_content LIKE '\''%enable\":\"1%'\'')	THEN 'TRUE' ELSE 'FALSE' END) as hasPayOnline FROM wp_posts wp WHERE wp.ID=$formID;' --skip-column-names;" 2>/dev/null)
    postContentJSON=$(ssh -n wwp-prod -- "wp db query --path=$path 'SELECT post_content FROM wp_posts wp WHERE wp.ID=$formID;' --skip-column-names;" | ggrep -oP '(?<="id_inst":)"([^"]*)' 2>/dev/null)
    numberOfEntries=$(ssh -n wwp-prod -- "wp db query --path=$path 'SELECT COUNT(*) as numberOfEntries FROM wp_wpforms_entries WHERE form_id=$formID;' --skip-column-names;" 2>/dev/null)
    echo "$path|$formID|$postTitle|$hasUploadField|$hasPayOnline|$hasPayOnline|$postContentJSON|$numberOfEntries|"
  done
done < "$input"