import Foundation

/// Shared search JS injected into WKWebView pages.
/// Provides `doupiSearch(query)` and `doupiNavigate(dir)` functions.
/// Injected once per page via `didFinish` navigation delegate or inline in HTML.
enum SearchJS {

    /// CSS for search highlights — injected into every page.
    static let styleCSS = """
    mark.doupi-search{background:rgba(93,154,50,0.35);color:inherit;border-radius:2px}mark.doupi-current{background:rgba(93,154,50,0.65);outline:1px solid rgba(93,154,50,0.8);border-radius:2px}
    """

    /// Full JS injected on `didFinish` for WebView / MarkdownView.
    static let injectionScript = """
    (function(){
      if(window._doupiInjected)return;
      window._doupiInjected=true;
      var s=document.createElement('style');
      s.textContent='\(styleCSS.replacingOccurrences(of: "'", with: "\\'"))';
      document.head.appendChild(s);
      \(functionsJS)
    })();
    """

    /// Core functions (also embedded inline in CodeView HTML).
    static let functionsJS = """
    var _doupiMatches=[];var _doupiCurrent=-1;
    function doupiSearch(q){
      document.querySelectorAll('mark.doupi-search,mark.doupi-current').forEach(function(m){var p=m.parentNode;while(m.firstChild)p.insertBefore(m.firstChild,m);p.removeChild(m)});
      _doupiMatches=[];_doupiCurrent=-1;
      if(!q)return JSON.stringify({count:0,current:-1});
      var w=document.createTreeWalker(document.body,4,null),ql=q.toLowerCase(),n,r;
      while(n=w.nextNode()){var p=n.parentNode;if(p&&(p.nodeName==='MARK'||p.nodeName==='SCRIPT'||p.nodeName==='STYLE'))continue;
      var t=n.textContent,i=t.toLowerCase().indexOf(ql);
      if(i>=0){r=document.createRange();r.setStart(n,i);r.setEnd(n,i+q.length);
      try{var mk=document.createElement('mark');mk.className='doupi-search';r.surroundContents(mk);_doupiMatches.push(mk);w.currentNode=mk}catch(e){}}}
      return JSON.stringify({count:_doupiMatches.length,current:_doupiCurrent});
    }
    function doupiNavigate(d){
      if(_doupiMatches.length===0)return -1;
      if(_doupiCurrent>=0&&_doupiCurrent<_doupiMatches.length)_doupiMatches[_doupiCurrent].className='doupi-search';
      _doupiCurrent+=d;
      if(_doupiCurrent>=_doupiMatches.length)_doupiCurrent=0;
      if(_doupiCurrent<0)_doupiCurrent=_doupiMatches.length-1;
      _doupiMatches[_doupiCurrent].className='doupi-current';
      _doupiMatches[_doupiCurrent].scrollIntoView({behavior:'smooth',block:'center'});
      return _doupiCurrent;
    }
    """
}
