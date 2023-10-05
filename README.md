The scripts in this directory together form the *osmtools* suite.

Originally written by Frederik Ramm <frederik@remote.org>, public domain.

The scripts require Perl and the LWP module (`libwww-perl` on Ubuntu et al., [Strawberry Perl](https://strawberryperl.com/) on Windows).

Package Contents
----------------

| Script  | Module  | Description  |
|---|---|---|
| `batch_redaction.pl`  | `BatchRedaction.pm`  | applies redactions to a list of elements  |
| `block.pl` | `Block.pm`  | creates user blocks  |
| `changeset.pl`  | `Changeset.pm`  | opens and closes changesets  |
| `changeset_graph.pl`  | `ChangesetGraph.pm`  | draws changeset dependency graph  |
| `complex_revert.pl`  |   | reverts a group of interdependent changesets  |
| `delete.pl`  | `Delete.pm`  | deletes or redacts an object  |
| `modify.pl`  | `Modify.pm`  | modifies tags of an object  |
| `note.pl`  | `Note.pm`  | hides notes  |
| `quickdelnodes.pl`  |   | deletes many nodes quickly  |
| `redaction.pl`  | `Redaction.pm`  | creates and applies redactions  |
| `revert.pl`  | `Revert.pm`  | reverts a whole changeset  |
| `trace.pl`  | `Trace.pm`  | uploads gpx traces  |
| `tokens.pl`  |   | requests oauth2 login tokens  |
| `undelete.pl`  | `Undelete.pm`  | undeletes an object; see comment in-file for differences to undo  |
| `undo.pl`  | `Undo.pm`  | undoes one change to one object  |
| `user_changesets.pl`  | `UserChangesets.pm`  | bulk downloads changesets by given user; there are also simpler shell script versions listed below  |
| `download_changesets.sh`  |   | bulk downloads changesets by given user name  |
| `download_changesets_uid.sh`  |   | bulk downloads changesets by given user id  |

Design "Philosophy"
-------------------

Most functionality is implemented as individual Perl modules (`.pm`). They do not have a namespace because we want people to be able to run everything from the current directory. If you create a Perl module named `Osm::Api`, then it has to reside in a subdirectory named `Osm` which tends to get confusing, at least for me.

We're not using any libraries for XML reading and writing in most of the scripts, just plain regular expressions.

We're not creating any OO interfaces.

In addition to the modules, there are simple perl scripts (`.pl`) that can be called from the command line and that provide a command line interface to what the modules do.

If you want to create some hyper cool object oriented undo/redo manager using all the latest libraries and technologies and design patterns, feel free to cannibalize the hell out of this code and make your own.

Act Responsibly
---------------

These scripts enable you to revert edits done by other people. Never do this unless you are absolutely sure that the edit in question is either malicious or accidental. Make an effort to talk to the user beforehand and afterwards. Always be kind to other mappers, and always assume that if they did something wrong it must have been an error, a misunderstanding, or their cat chasing fluff across the keyboard!

When in doubt, discuss things on the mailing list before you act (see [lists.openstreetmap.org](https://lists.openstreetmap.org/)). Also, [read the Wiki article on automated edits here](https://wiki.openstreetmap.org/wiki/Automated_Edits).

These scripts do not have safety nets. Be sure that you feel confident to fix anything you might break. If you do not know your PUTs from your GETs, if you do not know the details of [API 0.6](https://wiki.openstreetmap.org/wiki/API_v0.6), or know what changesets are and how they work, then DO NOT USE THIS SOFTWARE.

Configuration
-------------

You will have to create a file named `.osmtoolsrc` in your home directory containing the URL of the OSM server to use. The first thing to specify is the server to work with. The server URL must be complete up to the API version number and the slash afterwards, so:

    apiurl=https://api06.dev.openstreetmap.org/api/0.6/

The next step is to add the oauth2 client id of *osmtools*. This step is not required for servers where *osmtools* is already registered with a built-in id, which are:

- main OSM server
- [sandbox OSM server](https://wiki.openstreetmap.org/wiki/Sandbox_for_editing#Experiment_with_the_API_(advanced))
- [OpenHistoricalMap](https://wiki.openstreetmap.org/wiki/Open_Historical_Map)

If your server is not in the list above and you don't have a client id for *osmtools* on that server, you'll have to register *osmtools* as an oauth2 app. This process is described in the next section. Once you have the id, you'll need to add it to `.osmtoolsrc`:

    oauth2_client_id=1234567890zxcvbasdfgqwert

The next step is usually to request authorization tokens. This request will happen automatically if any operation requiring user login is run. However, since it requires user input, it may fail with scripts reading from stdin. Therefore it's safer to request tokens before running any other scripts by executing:

    tokens.pl request

You will be prompted to open a link to a confirmation page, then to copy the code. The received tokens will be saved to `.osmtoolsrc`.

Alternatively, if you want to avoid using oauth2, registering an application, setting up ids and tokens, you may use basic authorization. In this case you have to provide your username and password. Some operation require username and password anyway, see the "SCRAPE" section below.

    username=fred
    password=test

If your username or password is not specified in your `.osmtoolsrc` file, these scripts will look for `OSMTOOLS_USERNAME` and `OSMTOOLS_PASSWORD` environment variables. As a last resort, you will be prompted for a user name or password on the command line (requires the `Term::ReadKey` module).

By default, all tools will run in "dry run" mode, so no changes will be actually written and all write requests will be considered successful. Add the `dryrun=0` parameter to the file for live action.

By default, "dry run" also enables "debug" so you are shown the requests made. If you want to keep debug mode when setting `dryrun=0`, explicitly set `debug=1`. There's also `debug_request_headers` and `debug_request_body` to print out details about the HTML messages, and the same for responses.

Register osmtools as a oauth2 app
---------------------------------

1. Go to the `oauth2/applications/new` page of your *openstreetmap-website* server ([Example](https://api06.dev.openstreetmap.org/oauth2/applications/new)).
2. For Name enter `osmtools` or anything else to identify the application. This name will be shown to users when they grant permissions to *osmtools*.
3. For *Redirect URIs* enter:
    ```
    urn:ietf:wg:oauth:2.0:oob
    ```
4. Uncheck *Confidential application*
5. In *Permissions* check:
    - *Read user preferences*
    - *Modify the map*
    - *Read private GPS traces*
    - *Upload GPS traces*
    - *Modify notes*
6. Click *Register* or *Create Oauth2 application* below the registration form.
7. Add `oauth2_client_id=...` with the application *Client ID* to your `.osmtoolsrc` file.

You don't need to register *osmtools* on `api06.dev.openstreetmap.org`, `api.openstreetmap.org` and `www.openhistoricalmap.org` servers. The scripts have app ids built in for these servers. You can set `oauth2_client_id` to an empty value to refuse to use oauth2 on these servers and go back to basic login/password authorization.

SCRAPE SCRAPE SCRAPE
--------------------

Not everything these scripts do is actually exposed in proper API calls; for the creation of redactions and blocks, the scripts have to resort to actually "playing browser" and going through OSM's login page, set up a session, and then submit the right forms. Needless to say, these hacks are more likely to break than proper API access.
