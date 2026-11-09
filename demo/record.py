"""Capture the real plugin in an isolated Rex session. Run after demo setup."""
import subprocess,time,json
from pathlib import Path
ROOT=Path(__file__).resolve().parent
S='slop-demo'
def rex(*a):return subprocess.check_output(['rex',a[0],'-s',S,*a[1:]],text=True)
def text(s):rex('send',s)
def key(k):rex('send-key',k)
scenes=[]
def snap(title,caption,seconds=4):
    time.sleep(.5)
    n=len(scenes); (ROOT/'captures'/f'{n:02}.html').write_text(rex('capture','--format=html'))
    plain=rex('capture');(ROOT/'captures'/f'{n:02}.txt').write_text(plain)
    scenes.append(dict(title=title,caption=caption,seconds=seconds,file=f'{n:02}.html'))
def cmd(c):text(':'+c);key('enter');time.sleep(.7)
snap('Review code where you edit it','slop.nvim  /  native Neovim code review',3)
text(':Slop');snap('Start a review',':Slop  finds the PR and loads changed hunks',2);key('enter');time.sleep(2)
cmd('copen 5');snap('Changes in native quickfix','Gitsigns marks the diff; quickfix lists the hunks',4)
cmd('wincmd p');text(':cnext');snap('Move between hunks',':cnext  /  :cprevious',2);key('enter');time.sleep(.6)
cmd('cclose');snap('Stay in your source file','Jump straight to the next change',3)
text(':Slop comment');snap('Comment on a line',':Slop comment',2);key('enter');time.sleep(.5)
text('iCould we keep the word "Page" here?\nIt makes the status line easier to scan.');key('escape');snap('Write ordinary Markdown','A normal buffer, with all your editing commands',4)
cmd('write');snap('Save a draft',':write  saves the comment without publishing the review',3)
cmd('quit');cmd('5,6Slop suggest');snap('Suggest a replacement',':5,6Slop suggest  inserts the selected source lines',3)
cmd("lua vim.api.nvim_buf_set_lines(0, 0, -1, false, {'Handle missing arguments as well as negative values.', '', '```suggestion', '  page = math.max(1, page or 1)', '  size = math.max(1, size or 20)', '```'})")
snap('Propose the exact edit','Edit the fenced suggestion using normal Vim commands',4)
cmd('wq');cmd('Slop drafts');snap('Manage the draft review',':Slop drafts  /  Enter to edit  /  dd then :w to delete',4)
cmd('quit');cmd('Slop submit-comment');text('iTwo small suggestions before this lands.\nThanks for adding the input checks!');key('escape');snap('Add a review summary',':Slop submit-comment',3)
cmd('write');snap('Submit when ready',':write  submits the summary and draft comments together',4)
state=json.loads(Path('/tmp/slop-video-repo/github.json').read_text())
assert len(state['submitted']['comments'])==2,state
assert 'Two small suggestions' in state['submitted']['body']
(ROOT/'scenes.json').write_text(json.dumps(scenes,indent=2))
print(f'Captured {len(scenes)} scenes; verified two submitted comments and summary.')
