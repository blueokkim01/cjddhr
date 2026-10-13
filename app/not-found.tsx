import Link from "next/link";

export default function NotFound() {
  return (
    <main id="main" className="mx-auto flex w-full max-w-md flex-1 flex-col items-center justify-center gap-4 p-6 text-center">
      <h1 className="text-xl font-semibold">페이지를 찾을 수 없어요</h1>
      <p className="text-muted-foreground">주소를 다시 확인하거나 처음 화면으로 돌아가세요.</p>
      <Link href="/" className="font-medium text-primary underline underline-offset-4">
        처음으로
      </Link>
    </main>
  );
}
