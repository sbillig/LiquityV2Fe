"""Small source helper for the fixed metadata templates, not a general parser."""
import re

def normalize_joins(source):
    def scan(text, start, split=False):
        depth=0;quote=None;escaped=False;parts=[];begin=start
        for i in range(start,len(text)):
            c=text[i]
            if quote:
                if escaped:escaped=False
                elif c=='\\':escaped=True
                elif c==quote:quote=None
                continue
            if c in ('"',"'"):quote=c;continue
            if c in '([':depth+=1
            elif c in ')]':
                if depth==0:return i
                depth-=1
            elif c==',' and depth==0 and split:parts.append(text[begin:i]);begin=i+1
        if split:return parts+[text[begin:]]
        raise ValueError('Unclosed join expression')
    output='';start=0
    for_match=re.compile(r'\bjoin\(')
    while (match:=for_match.search(source,start)):
        end=scan(source,match.end())
        content=source[match.end():end].strip()
        if content.startswith('['):
            content=content[1:-1]
        if content.startswith('(') and content.endswith(')'):content=content[1:-1]
        parts=scan(content,0,True)
        args=[]
        for part in parts:
            part=normalize_joins(part.strip())
            if part.startswith('"') and part.endswith('"'):part='fragment('+part+')'
            args.append(part)
        result='text('+args[0]+')'
        if len(args)>1:
            result='cat('+args[0]+', '+args[1]+')'
            for arg in args[2:]:result='cat('+result+'.as_bytes(), '+arg+')'
        output+=source[start:match.start()]+result
        start=end+1
    return output+source[start:]
