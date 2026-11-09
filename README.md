# sprints.nvim

Built inside my www.github.com/Manny-S-04/NvimSetup config, the commit history is there.

Zoho Sprints in Neovim: your sprint, the backlog and work items in buffers, with status
changes, assignment and comments, without opening the browser. A port of
[jira.nvim](https://github.com/Manny-S-04/jira.nvim) to Zoho's API, keeping its layering:

```
lua/sprints/
  config.lua          defaults <- env <- setup() opts; data-centre hosts
  html.lua            Zoho rich text (HTML) -> plain lines   (jira.nvim: adf.lua)
  api/                no buffers or windows in here
    client.lua        curl transport, secrets via stdin, Zoho's HTTP-200 errors
    auth.lua          OAuth refresh-token -> 1h access token, cached, shared refresh
    decode.lua        Zoho's <x>Ids / <x>JObj / <x>_prop tables -> rows
    async.lua         parallel calls, pagination
    workspace.lua     teams, projects, statuses/types/priorities/users, "me"
    sprints.lua       sprints, active sprint, backlog id
    items.lua         list, get (+comments), status, owners, comment
  ui/                 render (pure), item, list, comment, context (pickers)
```

Requires Neovim 0.10+ and `curl`.

## Setup

Zoho has no personal API tokens; it uses OAuth. A **Self Client** gives you a refresh token
that doesn't expire, and the plugin mints short-lived access tokens from it.

1. Find your data centre from your Sprints URL: `sprints.zoho.eu` → `eu`, `.com` → `com`,
   `.in`, `.com.au` (`au`), `.jp`, `.ca`, `.uk`, `.sa`.
2. Go to `https://api-console.zoho.<dc>` → **Add Client** → **Self Client**. Note the client
   id and secret.
3. **Generate Code** with these scopes (10-minute expiry is fine):

   ```
   ZohoSprints.teams.READ,ZohoSprints.projects.READ,ZohoSprints.sprints.READ,ZohoSprints.items.ALL,ZohoSprints.comments.ALL,ZohoSprints.teamusers.READ,ZohoSprints.projectusers.READ
   ```
4. Exchange the code for a refresh token (within 10 minutes):

   ```sh
   curl -X POST "https://accounts.zoho.<dc>/oauth/v2/token" \
     -d grant_type=authorization_code -d code=<CODE> \
     -d client_id=<ID> -d client_secret=<SECRET>
   ```
   Keep `refresh_token` from the response.
5. Export (e.g. in your shell profile or a secrets manager, not this repo):

   ```sh
   ZOHO_DC=eu
   ZOHO_CLIENT_ID=...
   ZOHO_CLIENT_SECRET=...
   ZOHO_REFRESH_TOKEN=...
   ZOHO_SPRINTS_TEAM=...      # optional: else you pick (or the only one is used)
   ZOHO_SPRINTS_PROJECT=...   # optional: else you pick
   ZOHO_SPRINTS_USER=...      # or ZOHO_EMAIL=you@work, to find your user id
   ```
6. `:checkhealth sprints` checks the config and that a token can be minted.

## Commands

| Command | Key | |
|---|---|---|
| `:SprintsMine` | `<leader>sm` | Your items in the active sprint(s) |
| `:SprintsBoard` | `<leader>sb` | Active sprint grouped by status |
| `:SprintsBacklog` | `<leader>sl` | The backlog |
| `:SprintsNew` | `<leader>sn` | New item (`:w` creates) |
| `:SprintsItem [NO]` | `<leader>si` | Open an item: `I12`, `12`, `#12`, `PRJ-I12`, default word under cursor |
| `:SprintsSearch WORDS` | `<leader>ss` | Items whose title has every word (active sprint + backlog) |
| `:SprintsSprint [pick]` | | Active sprint(s); `pick` chooses any (active first) |
| `:SprintsProject` | | Switch project for the session |
| `:SprintsRaw <what>` | | Raw API response: `teams projects project sprints statuses users` |
| `:Sprints` | | Help |

**List**, `<CR>` open · `n` new item here · `b` board view · `m` only mine · `yk`/`yu` copy key/link ·
`gx` browser · `r` refresh · `g?` help

**Item**, `s` status · `e` edit everything (`:w` saves) · `c` comment (`:w` posts) · `a` add/remove me ·
`o` add/remove an owner · `A` remove all owners (asks) · `p` priority · `yk`/`yu` copy key/link · `gx` browser ·
`gR` raw response · `r` refresh · `g?` help

### Editing and creating

`e` on an item and `:SprintsNew` / `n` open the same kind of buffer:

```
# Title

Status: In Progress        <- allowed values show as virtual text
Type: Bug
Priority: High
Points: 3
Owners: Manny Singh, Sam   <- full names, first names, "me"; empty = none
---
Description in **markdown**.
```

`:w` saves; only fields you changed are sent. Values match case-insensitively and by unique
word prefix (`prog` → In Progress). A bad value is explained and your text is kept. New items
also get a `Sprint:` line (active/upcoming sprints or `Backlog`).

Comments and descriptions are written in markdown and stored as the HTML Zoho's web UI shows:
bold, italics, code, links, lists, headings and code blocks survive the round trip.

## Differences from jira.nvim, and why

- **No JQL / `:JiraFind`.** Zoho's API has no query language; lists are by sprint, backlog or owner.
- **No transitions.** Zoho statuses aren't gated by a workflow in the API, so `s` offers every
  project status except the current one.
- **Items need four ids** (team, project, sprint, item), so buffers carry a `ref`, and
  `:SprintsItem` scans the active sprint(s) + backlog: there's no get-by-number call.
- **"Mine" filters client-side.** The server-side owner filter needs board lane ids that differ per project.
- **Assign to me replaces the owner list.** Zoho items can have several owners.
- **Not ported yet:** the harpoon worklist and parent/children navigation (Zoho has epics and
  sub-items rather than Jira's parent field).
- **Still needs the browser:** moving an item between sprints, editing or deleting comments,
  logging time, attachments. Each needs an endpoint that isn't confirmed yet.

## Status of the API mapping

Zoho's API reference is a JavaScript app, so parts of this were built from working
third-party clients rather than the reference itself. The guesses are isolated so each is a
one-line fix:

- `items.ENDPOINTS`: the comments (`/notes/`) path and field (**unverified**); update-item field
  names, assumed to match create's (confirmed) plus `statusid` (**unverified**).
- `items.FIELDS`: candidate field names per attribute; the first one present wins.
- `sprints.SPRINT_TYPES`: which `sprintType` code means "active". **Unverified.**

`gR` in an item and `:SprintsRaw` show the real payloads to check these against. If comments
fail, the item still opens with the reason shown under *Comments*.

## Testing

`api_url` / `accounts_url` (env `ZOHO_SPRINTS_API_URL` / `ZOHO_ACCOUNTS_URL`) point the plugin at
another host, e.g. a local mock server for manual testing.



```sh
nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/ { minimal_init = 'tests/minimal_init.lua', sequential = true }"
```
