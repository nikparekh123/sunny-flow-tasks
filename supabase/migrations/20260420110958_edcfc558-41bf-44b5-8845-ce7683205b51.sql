-- Create reports table
CREATE TABLE public.reports (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  title TEXT NOT NULL,
  tickers TEXT[] DEFAULT '{}',
  report_type TEXT NOT NULL CHECK (report_type IN ('single','macro','theme','earn')),
  primary_sector TEXT,
  sectors TEXT[] DEFAULT '{}',
  author TEXT,
  published_at DATE,
  read_minutes INTEGER,
  tags TEXT[] DEFAULT '{}',
  summary TEXT,
  visibility TEXT NOT NULL DEFAULT 'Team' CHECK (visibility IN ('Team','Firm-wide','Private')),
  file_path TEXT,
  starred BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.reports ENABLE ROW LEVEL SECURITY;

-- Open policies (no auth yet)
CREATE POLICY "Public can view reports"
  ON public.reports FOR SELECT USING (true);

CREATE POLICY "Public can insert reports"
  ON public.reports FOR INSERT WITH CHECK (true);

CREATE POLICY "Public can update reports"
  ON public.reports FOR UPDATE USING (true);

CREATE POLICY "Public can delete reports"
  ON public.reports FOR DELETE USING (true);

CREATE INDEX idx_reports_published_at ON public.reports(published_at DESC);
CREATE INDEX idx_reports_report_type ON public.reports(report_type);

-- Storage bucket for HTML report files
INSERT INTO storage.buckets (id, name, public)
VALUES ('reports', 'reports', true);

-- Open storage policies for the reports bucket
CREATE POLICY "Public can view report files"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'reports');

CREATE POLICY "Public can upload report files"
  ON storage.objects FOR INSERT
  WITH CHECK (bucket_id = 'reports');

CREATE POLICY "Public can update report files"
  ON storage.objects FOR UPDATE
  USING (bucket_id = 'reports');

CREATE POLICY "Public can delete report files"
  ON storage.objects FOR DELETE
  USING (bucket_id = 'reports');