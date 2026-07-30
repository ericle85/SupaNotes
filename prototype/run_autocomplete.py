import os
from autocomplete.autocomplete_pipeline import run_autocomplete_on_document


def print_single_suggestion(document_name: str, document_path: str) -> None:
    result = run_autocomplete_on_document(document_path)
    print(f"document:    {document_name}")
    print(f"current:     {result.current_line_text}")
    print(f"operation:   {result.classified_intent.operation.name}")
    if result.suggestion.has_suggestion:
        print(f"next line:   {result.suggestion.suggested_text}")
    else:
        print(f"no suggestion: {result.suggestion.diagnostic_reason}")


def run_all_documents_in_folder(documents_folder: str) -> None:
    document_names = sorted(name for name in os.listdir(documents_folder) if name.endswith(".txt"))
    for document_name in document_names:
        document_path = os.path.join(documents_folder, document_name)
        print_single_suggestion(document_name, document_path)
        print()


if __name__ == "__main__":
    prototype_directory = os.path.dirname(os.path.abspath(__file__))
    documents_directory = os.path.join(prototype_directory, "documents")
    run_all_documents_in_folder(documents_directory)
