// supabase/migrations 와 짝을 이루는 DB 타입.
// Docker가 있는 환경에서는 `npm run db:types`로 생성한 결과와 비교해 갱신한다.
// Insert/Update 타입은 마이그레이션의 컬럼 권한(grant)과 맞춰 두었다.
// 예를 들어 reading_logs.Insert에 user_id·log_date가 없는 것은 DB가 직접 정하기 때문이다.

export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[];

export type AgeGroup = "child_u14" | "teen" | "adult";
export type UserRole = "user" | "admin";
export type AccountStatus = "pending_guardian" | "active" | "suspended";
export type GoalType = "books" | "pages" | "days";
export type ChallengeVisibility = "public" | "group_only";
export type TargetAge = "all" | "teen_only" | "adult_only";
export type ReviewStatus = "none" | "pending_review" | "hidden" | "restored";
export type ReportReason =
  | "spam"
  | "abuse"
  | "sexual"
  | "personal_info"
  | "self_harm"
  | "inappropriate"
  | "other";
export type ReportStatus = "pending" | "resolved";
export type ReactionKind = "clap" | "fire" | "books" | "muscle" | "heart";

type Fk<Name extends string, Col extends string, Ref extends string, RefCol extends string = "id"> = {
  foreignKeyName: Name;
  columns: [Col];
  isOneToOne: false;
  referencedRelation: Ref;
  referencedColumns: [RefCol];
};

export type Database = {
  __InternalSupabase: {
    PostgrestVersion: "13";
  };
  public: {
    Tables: {
      profiles: {
        Row: {
          id: string;
          nickname: string;
          age_group: AgeGroup;
          role: UserRole;
          status: AccountStatus;
          created_at: string;
          updated_at: string;
        };
        Insert: never;
        Update: { nickname?: string };
        Relationships: [];
      };
      profile_private: {
        Row: {
          id: string;
          birth_year: number;
          guardian_email: string | null;
          guardian_consented_at: string | null;
          created_at: string;
        };
        Insert: never;
        Update: never;
        Relationships: [Fk<"profile_private_id_fkey", "id", "profiles">];
      };
      guardian_consents: {
        // service_role 전용
        Row: {
          id: string;
          user_id: string;
          guardian_email: string;
          token_hash: string;
          expires_at: string;
          consented_at: string | null;
          created_at: string;
        };
        Insert: {
          user_id: string;
          guardian_email: string;
          token_hash: string;
          expires_at: string;
        };
        Update: { consented_at?: string | null };
        Relationships: [Fk<"guardian_consents_user_id_fkey", "user_id", "profiles">];
      };
      groups: {
        Row: {
          id: string;
          name: string;
          description: string;
          owner_id: string;
          invite_code: string;
          created_at: string;
        };
        Insert: { name: string; description?: string };
        Update: { name?: string; description?: string };
        Relationships: [Fk<"groups_owner_id_fkey", "owner_id", "profiles">];
      };
      group_members: {
        Row: { group_id: string; user_id: string; joined_at: string };
        Insert: never;
        Update: never;
        Relationships: [
          Fk<"group_members_group_id_fkey", "group_id", "groups">,
          Fk<"group_members_user_id_fkey", "user_id", "profiles">,
        ];
      };
      challenges: {
        Row: {
          id: string;
          group_id: string | null;
          title: string;
          description: string;
          start_date: string;
          end_date: string;
          goal_type: GoalType;
          goal_value: number;
          visibility: ChallengeVisibility;
          target_age: TargetAge;
          member_count: number;
          created_by: string | null;
          created_at: string;
        };
        Insert: {
          group_id?: string | null;
          title: string;
          description?: string;
          start_date: string;
          end_date: string;
          goal_type: GoalType;
          goal_value: number;
          visibility?: ChallengeVisibility;
          target_age?: TargetAge;
        };
        Update: { title?: string; description?: string };
        Relationships: [
          Fk<"challenges_group_id_fkey", "group_id", "groups">,
          Fk<"challenges_created_by_fkey", "created_by", "profiles">,
        ];
      };
      challenge_members: {
        Row: { challenge_id: string; user_id: string; joined_at: string };
        Insert: { challenge_id: string };
        Update: never;
        Relationships: [
          Fk<"challenge_members_challenge_id_fkey", "challenge_id", "challenges">,
          Fk<"challenge_members_user_id_fkey", "user_id", "profiles">,
        ];
      };
      books: {
        Row: {
          id: string;
          isbn: string | null;
          title: string;
          author: string;
          publisher: string;
          thumbnail_url: string | null;
          source: "kakao" | "manual";
          created_by: string | null;
          created_at: string;
        };
        Insert: {
          isbn?: string | null;
          title: string;
          author?: string;
          publisher?: string;
          thumbnail_url?: string | null;
          source?: "kakao" | "manual";
        };
        Update: never;
        Relationships: [Fk<"books_created_by_fkey", "created_by", "profiles">];
      };
      reading_logs: {
        Row: {
          id: string;
          user_id: string;
          challenge_id: string;
          book_id: string;
          log_date: string;
          page_from: number | null;
          page_to: number | null;
          pages_read: number;
          minutes: number | null;
          comment: string;
          is_finished: boolean;
          image_path: string;
          image_hash: string;
          is_hidden: boolean;
          review_status: ReviewStatus;
          created_at: string;
        };
        Insert: {
          challenge_id: string;
          book_id: string;
          page_from?: number | null;
          page_to?: number | null;
          pages_read: number;
          minutes?: number | null;
          comment?: string;
          is_finished?: boolean;
          image_path: string;
          image_hash: string;
        };
        Update: never;
        Relationships: [
          Fk<"reading_logs_user_id_fkey", "user_id", "profiles">,
          Fk<"reading_logs_challenge_id_fkey", "challenge_id", "challenges">,
          Fk<"reading_logs_book_id_fkey", "book_id", "books">,
        ];
      };
      reactions: {
        Row: { reading_log_id: string; user_id: string; kind: ReactionKind; created_at: string };
        Insert: { reading_log_id: string; kind: ReactionKind };
        Update: never;
        Relationships: [
          Fk<"reactions_reading_log_id_fkey", "reading_log_id", "reading_logs">,
          Fk<"reactions_user_id_fkey", "user_id", "profiles">,
        ];
      };
      comments: {
        Row: {
          id: string;
          reading_log_id: string;
          user_id: string;
          body: string;
          is_hidden: boolean;
          review_status: ReviewStatus;
          created_at: string;
        };
        Insert: { reading_log_id: string; body: string };
        Update: never;
        Relationships: [
          Fk<"comments_reading_log_id_fkey", "reading_log_id", "reading_logs">,
          Fk<"comments_user_id_fkey", "user_id", "profiles">,
        ];
      };
      reports: {
        Row: {
          id: string;
          reporter_id: string;
          reading_log_id: string | null;
          comment_id: string | null;
          reason: ReportReason;
          detail: string;
          status: ReportStatus;
          resolved_by: string | null;
          resolved_at: string | null;
          created_at: string;
        };
        Insert: {
          reading_log_id?: string | null;
          comment_id?: string | null;
          reason: ReportReason;
          detail?: string;
        };
        Update: never;
        Relationships: [
          Fk<"reports_reporter_id_fkey", "reporter_id", "profiles">,
          Fk<"reports_reading_log_id_fkey", "reading_log_id", "reading_logs">,
          Fk<"reports_comment_id_fkey", "comment_id", "comments">,
          Fk<"reports_resolved_by_fkey", "resolved_by", "profiles">,
        ];
      };
      blocks: {
        Row: { blocker_id: string; blocked_id: string; created_at: string };
        Insert: { blocked_id: string };
        Update: never;
        Relationships: [
          Fk<"blocks_blocker_id_fkey", "blocker_id", "profiles">,
          Fk<"blocks_blocked_id_fkey", "blocked_id", "profiles">,
        ];
      };
      badges: {
        Row: { code: string; name: string; description: string; sort_order: number };
        Insert: never;
        Update: never;
        Relationships: [];
      };
      user_badges: {
        Row: {
          id: string;
          user_id: string;
          badge_code: string;
          challenge_id: string | null;
          awarded_at: string;
        };
        Insert: never;
        Update: never;
        Relationships: [
          Fk<"user_badges_user_id_fkey", "user_id", "profiles">,
          Fk<"user_badges_badge_code_fkey", "badge_code", "badges", "code">,
          Fk<"user_badges_challenge_id_fkey", "challenge_id", "challenges">,
        ];
      };
      banned_words: {
        Row: {
          id: number;
          word: string;
          normalized: string;
          created_by: string | null;
          created_at: string;
        };
        Insert: { word: string };
        Update: never;
        Relationships: [Fk<"banned_words_created_by_fkey", "created_by", "profiles">];
      };
    };
    Views: { [_ in never]: never };
    Functions: {
      check_banned_words: { Args: { p_text: string }; Returns: boolean };
      join_group_by_code: { Args: { p_code: string }; Returns: string };
      regenerate_invite_code: { Args: { p_group_id: string }; Returns: string };
      my_challenge_progress: { Args: { p_challenge_id: string }; Returns: number };
      my_current_streak: { Args: Record<string, never>; Returns: number };
      kst_today: { Args: Record<string, never>; Returns: string };
      admin_review_content: {
        Args: {
          p_reading_log_id: string | null;
          p_comment_id: string | null;
          p_decision: "keep_hidden" | "restore";
        };
        Returns: undefined;
      };
      admin_set_suspension: {
        Args: { p_user_id: string; p_suspend: boolean };
        Returns: AccountStatus;
      };
      confirm_guardian_consent: { Args: { p_token: string }; Returns: string };
    };
    Enums: {
      age_group: AgeGroup;
      user_role: UserRole;
      account_status: AccountStatus;
      goal_type: GoalType;
      challenge_visibility: ChallengeVisibility;
      target_age: TargetAge;
      review_status: ReviewStatus;
      report_reason: ReportReason;
      report_status: ReportStatus;
      reaction_kind: ReactionKind;
    };
    CompositeTypes: { [_ in never]: never };
  };
};

type PublicSchema = Database["public"];
export type Tables<T extends keyof PublicSchema["Tables"]> = PublicSchema["Tables"][T]["Row"];
export type TablesInsert<T extends keyof PublicSchema["Tables"]> = PublicSchema["Tables"][T]["Insert"];
export type TablesUpdate<T extends keyof PublicSchema["Tables"]> = PublicSchema["Tables"][T]["Update"];
