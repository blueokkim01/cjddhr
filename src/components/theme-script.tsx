// 첫 페인트 전에 다크 모드 클래스를 붙여 깜빡임을 막는다. 저장된 선택이 없으면 시스템 설정을 따른다.
const script = `(function(){try{var t=localStorage.getItem("theme");var d=t?t==="dark":matchMedia("(prefers-color-scheme: dark)").matches;document.documentElement.classList.toggle("dark",d)}catch(e){}})()`;

export function ThemeScript() {
  return <script dangerouslySetInnerHTML={{ __html: script }} />;
}
