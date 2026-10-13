export default function Loading() {
  return (
    <div role="status" aria-live="polite" className="flex flex-1 items-center justify-center p-8">
      <span className="size-8 animate-spin rounded-full border-4 border-muted border-t-primary" aria-hidden />
      <span className="sr-only">불러오는 중…</span>
    </div>
  );
}
