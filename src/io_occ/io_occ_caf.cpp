/****************************************************************************
** Copyright (c) 2016, Fougue SAS <https://www.fougue.pro>
** SPDX-License-Identifier: BSD-2-Clause
****************************************************************************/

#include "io_occ_caf.h"
#include "../base/document.h"
#include "../base/occ_progress_indicator.h"
#include "../base/io_system.h"
#include "../base/task_progress.h"
#include "../base/tkernel_utils.h"

#include <Transfer_TransientProcess.hxx>
#include <IGESCAFControl_Reader.hxx>
#include <IGESCAFControl_Writer.hxx>
#include <STEPCAFControl_Reader.hxx>
#include <STEPCAFControl_Writer.hxx>
#include <gsl/util>
#if OCC_VERSION_HEX >= OCC_VERSION_CHECK(7, 8, 0)
#  include <DESTEP_Parameters.hxx>
#  include <ShapeProcess.hxx>
#endif

namespace Mayo::IO::Private {

namespace {

// NOTE
// Maybe STEP/IGES CAF ReadFile() can be run concurrently(they should)
// But concurrent calls to Transfer() to the same target Document must be serialized

template<typename CafReaderType>
bool cafGenericReadFile(CafReaderType& reader, const FilePath& filepath, TaskProgress* /*progress*/)
{
    //readFile_prepare(reader);
    const IFSelect_ReturnStatus error = reader.ReadFile(filepath.u8string().c_str());
    return error == IFSelect_RetDone;
}

template<typename CafReaderType>
NCollection_Sequence<TDF_Label> cafGenericReadTransfer(CafReaderType& reader, DocumentPtr doc, TaskProgress* progress)
{
    auto indicator = makeOccHandle<OccProgressIndicator>(progress);
    const NCollection_Sequence<TDF_Label> seqMark = doc->xcaf().topLevelFreeShapes();
    OccHandle<TDocStd_Document> stdDoc = doc;
#if OCC_VERSION_HEX >= OCC_VERSION_CHECK(7, 5, 0)
    [[maybe_unused]]const bool okTransfer = reader.Transfer(stdDoc, indicator->Start());
#else
    OccHandle<XSControl_WorkSession> ws = Private::cafWorkSession(reader);
    ws->MapReader()->SetProgress(indicator);
    auto _ = gsl::finally([&]{ ws->MapReader()->SetProgress(nullptr); });
    const bool okTransfer = reader.Transfer(stdDoc);
#endif
    return doc->xcaf().diffTopLevelFreeShapes(seqMark);
}

template<typename CafWriterType>
bool cafGenericWriteTransfer(CafWriterType& writer, gsl::span<const ApplicationItem> appItems, TaskProgress* progress)
{
    auto indicator = makeOccHandle<OccProgressIndicator>(progress);
#if OCC_VERSION_HEX < OCC_VERSION_CHECK(7, 5, 0)
    Private::cafFinderProcess(writer)->SetProgress(indicator);
    auto _ = gsl::finally([&]{ Private::cafFinderProcess(writer)->SetProgress(nullptr); });
#endif

    bool okTransfer = true;
    System::visitUniqueItems(appItems, [&](const ApplicationItem& item) {
        if (!okTransfer)
            return; // Skip if already in error state

        bool okItemTransfer = false;
        if (item.isDocument())
            okItemTransfer = writer.Transfer(item.document());
        else if (item.isDocumentTreeNode())
            okItemTransfer = writer.Transfer(item.documentTreeNode().label());

        if (!okItemTransfer)
            okTransfer = false;
    });

    return okTransfer;
}

} // namespace

std::mutex& cafGlobalMutex()
{
    static std::mutex mutex;
    return mutex;
}

OccHandle<XSControl_WorkSession> cafWorkSession(const STEPCAFControl_Reader& reader) {
    return reader.Reader().WS();
}

OccHandle<XSControl_WorkSession> cafWorkSession(const IGESCAFControl_Reader& reader) {
    return reader.WS();
}

bool cafReadFile(IGESCAFControl_Reader& reader, const FilePath& filepath, TaskProgress* progress) {
    return cafGenericReadFile(reader, filepath, progress);
}

bool cafReadFile(STEPCAFControl_Reader& reader, const FilePath& filepath, TaskProgress* progress) {
    return cafGenericReadFile(reader, filepath, progress);
}

#if OCC_VERSION_HEX >= OCC_VERSION_CHECK(7, 8, 0)
namespace {

template<typename CafReaderType>
void cafGenericSetShapeFix(CafReaderType& reader, DE_ShapeFixParameters params, bool quick)
{
    if (quick) {
        // Skip the costly intersection/small-feature/orientation analysis done for each face and wire,
        // but keep the fixes needed to get a valid face(wire order/connection, gaps, seam, natural bounds)
        // Note: turning off FixFaceMode as a whole is faster but faulty(missing faces, wrong bounding box)
        using FixMode = DE_ShapeFixParameters::FixMode;
        params.FixIntersectingWiresMode = FixMode::NotFix;
        params.FixLoopWiresMode = FixMode::NotFix;
        params.FixSplitFaceMode = FixMode::NotFix;
        params.FixSmallAreaWireMode = FixMode::NotFix;
        params.RemoveSmallAreaFaceMode = FixMode::NotFix;
        params.FixSelfIntersectionMode = FixMode::NotFix;
        params.FixSelfIntersectingEdgeMode = FixMode::NotFix;
        params.FixIntersectingEdgesMode = FixMode::NotFix;
        params.FixNonAdjacentIntersectingEdgesMode = FixMode::NotFix;
        params.FixOrientationMode = FixMode::NotFix;
        params.FixSmallMode = FixMode::NotFix;
    }

    ShapeProcess::OperationsFlags flags;
    flags.set(ShapeProcess::Operation::FixShape);
    reader.SetShapeFixParameters(params);
    reader.SetShapeProcessFlags(flags);
}

} // namespace
#endif

void cafSetShapeFix(STEPCAFControl_Reader& reader, bool quick) {
#if OCC_VERSION_HEX >= OCC_VERSION_CHECK(7, 8, 0)
    cafGenericSetShapeFix(reader, DESTEP_Parameters::GetDefaultShapeFixParameters(), quick);
#else
    (void)reader; (void)quick;
#endif
}

NCollection_Sequence<TDF_Label> cafTransfer(IGESCAFControl_Reader& reader, DocumentPtr doc, TaskProgress* progress) {
    return cafGenericReadTransfer(reader, doc, progress);
}

NCollection_Sequence<TDF_Label> cafTransfer(STEPCAFControl_Reader& reader, DocumentPtr doc, TaskProgress* progress) {
    return cafGenericReadTransfer(reader, doc, progress);
}

OccHandle<Transfer_FinderProcess> cafFinderProcess(const IGESCAFControl_Writer& writer) {
    return writer.TransferProcess();
}

OccHandle<Transfer_FinderProcess> cafFinderProcess(const STEPCAFControl_Writer& writer) {
    return writer.Writer().WS()->TransferWriter()->FinderProcess();
}

bool cafTransfer(IGESCAFControl_Writer& writer, gsl::span<const ApplicationItem> appItems, TaskProgress* progress) {
    return cafGenericWriteTransfer(writer, appItems, progress);
}

bool cafTransfer(STEPCAFControl_Writer& writer, gsl::span<const ApplicationItem> appItems, TaskProgress* progress) {
    return cafGenericWriteTransfer(writer, appItems, progress);
}

} // namespace Mayo::IO::Private
