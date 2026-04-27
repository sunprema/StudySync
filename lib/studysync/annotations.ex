defmodule Studysync.Annotations do
  use Ash.Domain,
    otp_app: :studysync,
    extensions: [AshPhoenix]

  resources do
    resource Studysync.Annotations.Annotation do
      define :list_annotations, action: :read
      define :get_annotation, action: :read, get_by: [:id]

      define :create_comment,
        action: :create_comment,
        args: [:resource_id, :page_number, :rect, :text, :body]

      define :create_question,
        action: :create_question,
        args: [:resource_id, :page_number, :rect, :text, :body]

      define :create_puzzle,
        action: :create_puzzle,
        args: [:resource_id, :page_number, :rect, :text, :body]
    end

    resource Studysync.Annotations.AnnotationComment do
      define :list_replies, action: :read
      define :reply, action: :reply, args: [:annotation_id, :body]
    end
  end
end
