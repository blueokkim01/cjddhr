"use client";

export default function Error({ reset }: { error: Error & { digest?: string }; reset: () => void }) {
  return (
    <main id="main" className="mx-auto flex w-full max-w-md flex-1 flex-col items-center justify-center gap-4 p-6 text-center">
      <h1 className="text-xl font-semibold">문제가 생겼어요</h1>
      <p className="text-muted-foreground">잠시 후 다시 시도해 주세요.</p>
      <button
        type="button"
        onClick={reset}
        className="rounded-md bg-primary px-4 py-2 font-medium text-primary-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2"
      >
        다시 시도
      </button>
    </main>
  );
}
