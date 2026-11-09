"""Render styled Rex HTML captures to a captioned MP4 and looping GIF.
Dependencies: pillow, imageio-ffmpeg. Set DEMO_FONT to a monospace TTF.
"""
from html.parser import HTMLParser
from pathlib import Path
import json,re,os,subprocess
from PIL import Image,ImageDraw,ImageFont
import imageio_ffmpeg
ROOT=Path(__file__).resolve().parent
fontpath=os.environ.get('DEMO_FONT','/tmp/slop-demo-font.ttf')
font=ImageFont.truetype(fontpath,22)
titlefont=ImageFont.truetype(fontpath,27)
small=ImageFont.truetype(fontpath,16)
CW=font.getlength('M'); LH=27
class Capture(HTMLParser):
    def __init__(self,draw):super().__init__();self.draw=draw;self.styles=[];self.x=0;self.y=0
    def handle_starttag(self,tag,attrs):
        if tag!='div':return
        style=dict(attrs).get('style','')
        def color(name,default):
            m=re.search(r'(?:^|;)\s*'+name+r':\s*rgb\((\d+),\s*(\d+),\s*(\d+)\)',style)
            return tuple(map(int,m.groups())) if m else default
        self.styles.append((color('color',(188,188,188)),color('background-color',(28,28,28))))
    def handle_endtag(self,tag):
        if tag=='div' and self.styles:self.styles.pop()
    def handle_data(self,data):
        fg,bg=self.styles[-1] if self.styles else ((188,188,188),(28,28,28))
        for i,line in enumerate(data.split('\n')):
            if i:self.y+=LH;self.x=0
            if line:
                x=64+self.x; y=154+self.y;w=CW*len(line)
                self.draw.rectangle((x,y,x+w,y+LH),fill=bg)
                self.draw.text((x,y),line,font=font,fill=fg)
                self.x+=w
scenes=json.loads((ROOT/'scenes.json').read_text());frames=[]
for idx,s in enumerate(scenes):
    im=Image.new('RGB',(1280,960),'#10131b');d=ImageDraw.Draw(im)
    d.text((54,30),'slop.nvim',font=titlefont,fill='#d5a7ff')
    d.text((270,36),s['title'],font=font,fill='#edf0f7')
    d.rounded_rectangle((44,102,1236,925),radius=16,fill='#1c1c1c')
    for x,c in [(68,'#ff6b6b'),(91,'#e7c66b'),(114,'#7dc792')]:d.ellipse((x,118,x+10,128),fill=c)
    d.text((151,113),'Neovim  /  pagination.lua',font=small,fill='#999ca9')
    Capture(d).feed((ROOT/'captures'/s['file']).read_text().rstrip('\n'))
    d.rectangle((44,841,1236,925),fill='#222635')
    d.text((64,855),s['caption'],font=small,fill='#e1e6f5')
    d.text((64,889),'Real Neovim + Gitsigns  |  GitHub API simulated with test fixture',font=small,fill='#9b9faf')
    d.rectangle((44,923,44+1192*(idx+1)/len(scenes),927),fill='#b596e5')
    frames.append((im,s['seconds']))
frames[8][0].save(ROOT/'poster.png')
writer=imageio_ffmpeg.write_frames(str(ROOT/'slop-demo.mp4'),(1280,960),fps=12,codec='libx264',output_params=['-crf','20','-movflags','+faststart'])
writer.send(None)
for im,seconds in frames:
    for _ in range(seconds*12):writer.send(im.tobytes())
writer.close()
gif=[im.resize((960,720)).quantize(colors=128) for im,_ in frames]
gif[0].save(ROOT/'slop-demo.gif',save_all=True,append_images=gif[1:],duration=[s*1000 for _,s in frames],loop=0,optimize=False)
print('Rendered MP4 and GIF:',sum(s for _,s in frames),'seconds')
