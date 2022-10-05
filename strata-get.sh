#!/bin/ash

#  Main script to interact with lookatmystrata.
#
# Authentication is noteworthy - it doesn't use cookies or anything, and it also doesn't
#  use basic auth or tokens.  You authenticate once using plaintext creds and a special
#  endpoint, and then that TCP connection is authenticated - you have to reuse it for all
#  subsequent requests.  If you get disconnected, you start again from scratch.  It's odd.

STRATA_VERSION="${STRATA_VERSION:-1252}"
SEEN_FILE="${SINCE_FILE:-/config/.files-seen}"
JOIN=" - "
COUNT=0

if [ ! "$STRATA_USER" -o ! "$STRATA_CONTACT" -o ! "$STRATA_ID" -o ! "$STRATA_ROLE" ]
then
  echo "Incomplete config - please specifiy all of: STRATA_USER, STRATA_CONTACT, STRATA_ID, and STRATA_ROLE"
  exit 1
fi

if [ "$VERBOSE" ]
then
  CURL_OPTS="-vL"
else
  CURL_OPTS="-sL"
fi

[ ! -s "$SEEN_FILE" ] && logger -s -p 4 "$0 New SEEN_FILE - will populate it but not save any documents" && NO_SEND=Y

SAVE_TO="$2"
[ ! "$SAVE_TO" ] && SAVE_TO="/tmp"

while [ ! "$STRATA_PASS" ]
do
  read -sp "Strata password:" STRATA_PASS
done

logger -s "$0 Starting get with: User: $STRATA_USER, Contact: $STRATA_CONTACT, Strata ID: $STRATA_ID, Seen-file: $SEEN_FILE, Saving to: $SAVE_TO"

# Ensure any previous run didn't leave junk behind
rm -f /tmp/login.json /tmp/login.json.gz /tmp/documents.json /tmp/documents.json.gz

# Set standard headers in a file - makes curls easier to read
cat <<_EOH > /tmp/headers
User-Agent: Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:89.0) Gecko/20100101 Firefox/89.0
Accept: */*
Accept-Language: en-US,en;q=0.5
Accept-Encoding: gzip, deflate, br
Referer: https://www.lookatmystrata.com.au/
Origin: https://www.lookatmystrata.com.au
Connection: keep-alive
_EOH

LOGIN_STR='-H @/tmp/headers -H "Content-Type: application/json" -o /tmp/login.json.gz -d '\''{"username":"'"$STRATA_USER"'","password":"'"$STRATA_PASS"'","role":'"$STRATA_ROLE"',"version":'"$STRATA_VERSION"'}'\'' "https://prod-rock-sm-sp-portal-api.azurewebsites.net/api/agencies/'"$STRATA_ID"'/users/logon"'
[ "$VERBOSE" ] && logger -s "$0 LOGIN STRING: $LOGIN_STR"  # Yes, this will have your password in it.  But it's already in plaintext in the config file, so...

DOC_STR='--next -H @/tmp/headers -H "x-contactid: '"$STRATA_CONTACT"'" -H "x-username: '"$STRATA_USER"'" -o /tmp/documents.json.gz "https://prod-rock-sm-sp-portal-api.azurewebsites.net/api/agencies/'"$STRATA_ID"'/documents"'
logger -s "$0 Getting document list"
[ "$VERBOSE" ] && logger -s "$0 DOC STRING: $DOC_STR"

# This curl logs in and gets a list of all documents.  There is no filtering available, so you get the full list and do local filtering.
sh -c "curl ${CURL_OPTS} $LOGIN_STR $DOC_STR"
[ "$VERBOSE" ] && logger -s "$0 Done."

# Sometimes content is compressed, sometimes it isn't.  There are no headers set to help you, so you have to work it your yourself.
[ "$VERBOSE" ] && logger -s "$0 Output: $( ls -l /tmp/*json* )"
for FILE in /tmp/login.json.gz /tmp/documents.json.gz
do
  if file "$FILE" | grep -q "compressed data"
  then
    gunzip -f "$FILE"
  else
    mv "$FILE" "${FILE%.gz}"
  fi
done

if ! grep -q "documentId" /tmp/documents.json
then
  logger -s -p 3 "$0 Error getting documents - Login output: $(cat /tmp/login.json)"
  logger -s -p 3 "$0 Error getting documents - Documents output: $(cat /tmp/documents.json)"
  exit 0
fi

# This while block is fed from the end of the block via 'done < <( <command> )' - because that's how you set variables in a while read block without using a subshell
# Content is JSON doc, so we iterate over it, extract the fields we can use for each doc, and fetch it
while read LIBRARY FOLDER DOCID DATE TYPE CREDITOR
do
  [ ! "${LIBRARY}${FOLDER}${DOCID}${DATE}${TYPE}${CREDITOR}" ] && continue  # Completely empty row
  [ "$VERBOSE" ] && logger -s "$0  LIBRARY: $LIBRARY, FOLDER: $FOLDER, DOCID: $DOCID, DATE: $DATE, TYPE: $TYPE"
  if [ ! "$LIBRARY" -o ! "$FOLDER" -o ! "$DOCID" -o ! "$DATE" -o ! "$TYPE" ]
  then
    logger -s -p 4 "$0 *  Missing component, moving on.  LIBRARY: $LIBRARY, FOLDER: $FOLDER, DOCID: $DOCID, DATE: $DATE, TYPE: $TYPE"
    continue
  fi
  if [ ! "$CREDITOR" -o "$CREDITOR" == "null" ]
  then
    CREDITOR=""
  else
    CREDITOR="${JOIN}${CREDITOR}"
  fi
  DATE="${DATE%T*}" # Turn 2020-01-01T00:00:00+0000 into 2020-01-01.
  
  THIS_DOC_STR=' --next -H "x-contactid: '"$STRATA_CONTACT"'" -H "x-username: '"$STRATA_USER"'" -o "/tmp/'"${DOCID}"'.json" "https://prod-rock-sm-sp-portal-api.azurewebsites.net/api/agencies/'"${STRATA_ID}/documents/${LIBRARY}/${FOLDER}/${DOCID}\""
  [ "$VERBOSE" ] && logger -s "$0 Using curl: $THIS_DOC_STR"

  # This curl fetch the document identified by this iteration of the loop
  sh -c "curl ${CURL_OPTS} $LOGIN_STR $THIS_DOC_STR"

  OUTPUT="$( echo "${DATE}${JOIN}${TYPE}${CREDITOR}${JOIN}${DOCID}" | sed -E 's/[^a-zA-Z0-9.,:()+_-]+/_/g' )"
  FILE_EXT="$( jq -r .fileExtension "/tmp/${DOCID}.json" )"

  if [ "$NO_SEND" ]
  then
    logger -s -p 4 "$0 Marking ${OUTPUT}${FILE_EXT} as seen" && NO_SEND=Y
    echo "${OUTPUT}${FILE_EXT}" >> "$SEEN_FILE"
  else

    if grep -q "${OUTPUT}${FILE_EXT}" "$SEEN_FILE"
    then
      rm "/tmp/${DOCID}.json" 
      continue
    fi

    # The doc is not actually the doc at this point - it's a json object the the doc as base64 string.  Extract, decode, and rename.
    logger -s "$0 Getting doc $DOCID"
    jq -r .fileContents "/tmp/${DOCID}.json" | base64 -di > "${SAVE_TO}/${OUTPUT}${FILE_EXT}"

    if [ -s "${SAVE_TO}/${OUTPUT}${FILE_EXT}" ]
    then
      echo "${OUTPUT}${FILE_EXT}" >> "$SEEN_FILE"
    else
      logger -s "$0 WARNING - Didn't create output file ${SAVE_TO}/${OUTPUT}${FILE_EXT} successfully ($(ls -l ${SAVE_TO}/${OUTPUT}${FILE_EXT}))."
    fi

    COUNT=$((COUNT + 1))
    rm "/tmp/${DOCID}.json" 
  fi

## This is the source for the while loop
done << __EOF
  $( jq -r '.[]|([.libraryId, .folderId, .documentId, .date, (.documentType // empty |sub("[ \t]+"; "_"; "g")), (.creditor // empty |sub("[ \t]+"; "_"; "g"))])|@tsv' /tmp/documents.json )
__EOF

logger -s "$0 Got $COUNT docs."
rm -f /tmp/login.json /tmp/login.json.gz /tmp/documents.json /tmp/documents.json.gz
