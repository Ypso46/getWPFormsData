#!/bin/bash
# Usage: ./getFormsData.sh
#
# You can specify the files' name with:
#        SITES_URLS_FILE=sites_urls.txt \
#        DATA_CSV_FILE=forms_data.csv \
#        ./getFormsData.sh
#
# Use `--clear` to remove all the previously generated files
#

# Default files names
SITES_URLS_FILE="${SITES_URLS_FILE:-sites_urls.txt}"
DATA_CSV_FILE="${DATA_CSV_FILE:-forms_data.csv}"

if [ "$1" == '--clear' ]; then
  rm ${SITES_URLS_FILE} || true
  rm ${DATA_CSV_FILE} || true
fi

# Retrieve the sites that have the WPForms category
if [ ! -f "$SITES_URLS_FILE" ]; then
  echo "Retrieving sites list from wp-veritas.epfl.ch"
  curl -s https://wp-veritas.epfl.ch/api/v1/categories/WPForms/sites | jq -r '.[] | .url' > $SITES_URLS_FILE
fi

# Function that convert URL to site's path on the server
URLtoPath () {
  if [[ $1 =~ (www.epfl.ch/labs/) ]]; then
    lab_name=$(echo $1 | sed -n 's/https:\/\/www.epfl.ch\/labs\///gp' | tr -d '"')
    echo "/srv/labs/www.epfl.ch/htdocs/labs/${lab_name}"
  elif [[ $1 =~ (www.epfl.ch/research/) ]]; then
    research_name=$(echo $1 | sed -n 's/https:\/\/www.epfl.ch\/research\///gp' | tr -d '"')
    echo "/srv/www/www.epfl.ch/htdocs/research/domains/${research_name}"
  elif [[ $1 =~ (www.epfl.ch/schools/) ]]; then
    school_name=$(echo $1 | sed -n 's/https:\/\/www.epfl.ch\/schools\///gp' | tr -d '"')
    echo "/srv/www/www.epfl.ch/htdocs/schools/${school_name}"
  elif [[ $1 =~ (www.epfl.ch) ]]; then
    www_name=$(echo $1 | sed -n 's/https:\/\/www.epfl.ch\///gp' | tr -d '"')
    echo "/srv/www/www.epfl.ch/htdocs/${www_name}"
  elif [[ $1 =~ (inside.epfl.ch) ]]; then
    inside_name=$(echo $1 | sed -n 's/https:\/\/inside.epfl.ch\///gp' | tr -d '"')
    echo "/srv/inside/inside.epfl.ch/htdocs/${inside_name}"
  else
    subdomainlite_name=$(echo $1 | sed -n 's/https:\/\///gp' | sed -n 's/.epfl.ch\///gp' | tr -d '"')
    echo "/srv/subdomains-lite/${subdomainlite_name}.epfl.ch/htdocs/"
  fi
}

# Generate the $DATA_CSV_FILE CSV file based on each URL
echo "URL|path|formID|postTitle|hasUploadField|isPayOnlineEnable|payOnlineID|payOnlineEmail|numberOfEntries" > $DATA_CSV_FILE
while IFS= read -r url
do
  path=$(URLtoPath $url)
  echo "Running wp cli for $path ($url)"
  formIDs=$(ssh -n wwp-prod -- "wp db query --path=$path 'SELECT ID FROM wp_posts wp WHERE wp.post_type='\''wpforms'\'' AND wp.post_status='\''publish'\'';' --skip-column-names;" 2>/dev/null)
  if [ ! -z "$formIDs" ]; then
    for formID in $formIDs; do 
      postTitle=$(ssh -n wwp-prod -- "wp db query --path=$path 'SELECT post_title FROM wp_posts wp WHERE wp.ID=$formID;' --skip-column-names;" 2>/dev/null)
      hasUploadField=$(ssh -n wwp-prod -- "wp db query --path=$path 'SELECT (SELECT CASE WHEN EXISTS (SELECT post_title FROM wp_posts wp WHERE wp.ID=$formID AND post_content LIKE '\''%type\":\"file-upload%'\'')	THEN 'TRUE' ELSE 'FALSE' END) as hasUploadField FROM wp_posts wp WHERE wp.ID=$formID;' --skip-column-names;" 2>/dev/null)
      isPayOnlineEnable=$(ssh -n wwp-prod -- "wp db query --path=$path 'SELECT post_content FROM wp_posts wp WHERE wp.ID=$formID;' --skip-column-names;" | sed 's/\\\\/\\/g' | jq -r '.payments.epfl_payonline.enable // 0' 2>/dev/null)
      payOnlineID=$(ssh -n wwp-prod -- "wp db query --path=$path 'SELECT post_content FROM wp_posts wp WHERE wp.ID=$formID;' --skip-column-names;" | sed 's/\\\\/\\/g' | jq -r '.payments.epfl_payonline.id_inst // 0' 2>/dev/null)
      payOnlineEmail=$(ssh -n wwp-prod -- "wp db query --path=$path 'SELECT post_content FROM wp_posts wp WHERE wp.ID=$formID;' --skip-column-names;" | sed 's/\\\\/\\/g' | jq -r '.payments.epfl_payonline.email // 0' 2>/dev/null)
      numberOfEntries=$(ssh -n wwp-prod -- "wp db query --path=$path 'SELECT COUNT(*) as numberOfEntries FROM wp_wpforms_entries WHERE form_id=$formID;' --skip-column-names;" 2>/dev/null)
      echo "$url|$path|$formID|$postTitle|$hasUploadField|$isPayOnlineEnable|$payOnlineID|$payOnlineEmail|$numberOfEntries" >> $DATA_CSV_FILE
    done
  else 
    echo "$url|$path|-|-|0|0|-|-|0" >> $DATA_CSV_FILE
  fi
done < $SITES_URLS_FILE 
