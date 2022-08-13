# downloadmystrata
Automated interface to lookatmystrata.com.au

### Purpose
Many body corporate management companies outsource the document mangagement part of their role to lookatmystrata.com.au.
Unfortunately the portal is pretty dreadful to use as an end user.  Eventually I got sick of our managers saying "it's on the portal", and having to spend an hour finding, downloading, and renaming it - so I created a simple script to ease the burden.  I no longer have a need for this tool, but it may prove a headstart to others in the same position.

The concept is simple.  It's a docker container that periodically logs in to the portal, downloads any documents uploaded since the last time it checked, names them appropriately (as much as it can, given the information available), and saves them to a cloud location of your choice.  I used a microsoft onedrive shared folder, but anything you can configure with rclone will be fine.  Or save it to a local drive, I'm not the cloud police.

This is no longer maintained, was never really tested outside of doing the job I wanted, and will need modifications.  It's meant as a head start, not a fully functional tool.  I'll happily talk and answer questions, but don't expect any sort of support.


### Setup
- Copy config.sample to config.
  - Edit setup, set the vars to your strata details.  Use developer tools while logging to get anything you don't know
      STRATA_CONTACT="12345" # Login id provided to you
      STRATA_USER="00712345" # Probably your login id preceeded by 007
      STRATA_ID="123000"     # Your reseller's id
      STRATA_ROLE="2"        # Your role within the BC.  From memory use 1 for user, 2 for committe member, 3 for chair.
      STRATA_PASS="<secret>" # Your lookatmystrata password, in plaintext
      STRATA_VERSION="1252"  # Unsure, probably don't change it
      REMOTE="dest:path"     # The cloud destination you want rclone to save the docs to.  Format is `<rclone-dest>:<path>` where `<rclone-dest` is the `[rclone-dest]` from rclone.conf, and <path> is the location within that dest where you want to save it.  See rclone doc for more help on this.
  - Edit rclone.conf, add your configuration
- `docker build`
- `docker run`, or add a stanza to your docker-compose:
    downloadmystrata:
      image: downloadmystrata:latest
      volumes:
        - ./config:/config

The first run will not download any documents, but will set up the record of what it's already seen - subsequent runs will download everything new.
If you want to re-download something, remove it from `config/.files-seen`.  If you want to re-download everything, `echo -n > config/.files-seen`.
